import DependiEntities
import DependiDomain
import Foundation

/// Sets Dependi up in an app project: configuration, settings bundle, tool files and ignore rules.
public struct InitFeature: Sendable {
    private let files: any FileReading
    private let directories: any DirectoryListing
    private let writer: any FileWriting
    private let executables: any ExecutableMarking
    private let targets: any ApplicationTargetListing
    private let linkedProducts: any LinkedProductReading
    private let process: any ProcessRunning
    private let prompts: any Prompting
    private let output: any OutputWriting
    private let executablePath: String
    private let sourceRoot: String?
    private let wrapperText: String
    private let version: String

    private static let maximumExecutableBytes = 512 * 1024 * 1024
    private static let clashingNames = [
        "Acknowledgements.plist", "Acknowledgements", "com.mono0926.LicensePlist.plist",
        "com.mono0926.LicensePlist",
    ]

    /// Creates the feature with every outside capability, the running executable, the Dependi source
    /// folder if there is one, the wrapper script text and the version.
    public init(
        files: any FileReading, directories: any DirectoryListing, writer: any FileWriting,
        executables: any ExecutableMarking, targets: any ApplicationTargetListing,
        linkedProducts: any LinkedProductReading, process: any ProcessRunning,
        prompts: any Prompting,
        output: any OutputWriting, executablePath: String, sourceRoot: String?, wrapperText: String,
        version: String
    ) {
        self.files = files
        self.directories = directories
        self.writer = writer
        self.executables = executables
        self.targets = targets
        self.linkedProducts = linkedProducts
        self.process = process
        self.prompts = prompts
        self.output = output
        self.executablePath = executablePath
        self.sourceRoot = sourceRoot
        self.wrapperText = wrapperText
        self.version = version
    }

    /// Runs the wizard for the project at `projectPath`. A dry run reports and changes nothing.
    public func run(projectPath: String, isDryRun: Bool) throws(DomainError) -> InitOutcome {
        let location = try ProjectLocator(files: files, directories: directories, prompts: prompts)
            .locate(projectPath)
        let applications = try targets.applicationTargets(projectFilePath: location.projectFile)
        guard !applications.isEmpty else {
            throw .initRefused(reason: "the project has no application target.")
        }
        let target =
            applications.count == 1
            ? applications[0]
            : applications[
                try prompts.askChoice(
                    "Which application target shows the acknowledgements?", options: applications)]
        let linked = try linkedProducts.linkedProducts(
            projectFilePath: location.projectFile, targetName: target)
        if !linked.supportedPlatforms.isEmpty
            && linked.supportedPlatforms.allSatisfy({ $0 == "macosx" })
        {
            throw .initRefused(
                reason: "\(target) is a macOS app. macOS apps have no Settings.bundle.")
        }
        output.writeLine(
            "Dependi: project \(location.projectFile), target \(target), \(linked.products.count) package products."
        )
        let bundle = try findSettingsBundle(in: location.root)
        if isDryRun {
            report(location: location, bundle: bundle)
            return .reported
        }
        try writeConfiguration(location: location, linked: linked)
        try prepareSettingsBundle(
            at: bundle ?? location.root + "/Settings.bundle", root: location.root)
        try installTool(in: location.root)
        try updateIgnoreFile(in: location.root)
        printRunScript(root: location.root)
        return .installed
    }

    // MARK: Dry run

    private func report(location: ProjectLocation, bundle: String?) {
        output.writeLine("Dry run. Nothing is changed. A real run would:")
        output.writeLine("1. Write \(location.root)/.dependi.json if it is missing.")
        output.writeLine(
            "2. Add the Acknowledgements pane to \(bundle ?? location.root + "/Settings.bundle")/Root.plist."
        )
        output.writeLine(
            "3. Copy this program to \(location.root)/.dependi/bin/dependi and write .dependi/run.sh."
        )
        output.writeLine("4. Add .dependi/bin/ to \(location.root)/.gitignore.")
    }

    // MARK: Configuration

    private func writeConfiguration(location: ProjectLocation, linked: LinkedProductSet)
        throws(DomainError)
    {
        let path = location.root + "/.dependi.json"
        if files.exists(at: path) {
            output.writeLine("Dependi: kept the existing .dependi.json.")
            return
        }
        let normalizer = PackageIdentityNormalizer()
        let excludes = linked.localPackagePaths.filter { $0.hasPrefix(location.root + "/") }
            .map { normalizer.identity(forLocation: $0).value }.sorted()
        let commit = pinnedCommit()
        if commit == nil {
            output.writeLine(
                "Dependi: could not read the commit of this Dependi checkout. Add \"commit\" to .dependi.json."
            )
        }
        let settings = ToolConfiguration(
            excludes: excludes, manualEntries: [],
            gateConfigurations: ToolConfiguration.defaultGateConfigurations,
            sourcePackagesPath: nil, outputPath: nil, includeBuildTools: false,
            allowUnreached: false,
            processTimeoutSeconds: ToolConfiguration.defaultProcessTimeoutSeconds,
            runTimeoutSeconds: ToolConfiguration.defaultRunTimeoutSeconds, version: version,
            commit: commit)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(settings) else {
            throw .initRefused(reason: "the configuration could not be encoded.")
        }
        try writer.write(data + Data("\n".utf8), toPath: path)
        output.writeLine(
            "Dependi: wrote .dependi.json. Local packages are excluded: \(excludes.isEmpty ? "none" : excludes.joined(separator: ", "))."
        )
    }

    private func pinnedCommit() -> String? {
        guard let sourceRoot else { return nil }
        let request = ProcessRequest(
            executable: "/usr/bin/git", arguments: ["-C", sourceRoot, "rev-parse", "HEAD"],
            environment: ["PATH": "/usr/bin:/bin"], workingDirectory: nil, timeoutSeconds: 20,
            maximumOutputBytes: 4096)
        guard let result = try? process.run(request), result.exitStatus == 0 else { return nil }
        let text = String(decoding: result.standardOutput, as: UTF8.self).trimmingCharacters(
            in: .whitespacesAndNewlines)
        return text.range(of: #"^[0-9a-f]{40}$"#, options: .regularExpression) == nil ? nil : text
    }

    // MARK: Settings bundle

    private func findSettingsBundle(in root: String) throws(DomainError) -> String? {
        var found: [String] = []
        let top = try directories.topLevelNames(in: root)
        if top.contains("Settings.bundle") { found.append(root + "/Settings.bundle") }
        for name in top.sorted()
        where !name.hasPrefix(".") && name != "Pods" && name != "node_modules"
            && !name.hasSuffix(".xcodeproj") && name != "Settings.bundle"
        {
            guard let inner = try? directories.topLevelNames(in: root + "/" + name) else {
                continue
            }
            if inner.contains("Settings.bundle") {
                found.append(root + "/" + name + "/Settings.bundle")
            }
        }
        switch found.count {
        case 0: return nil
        case 1: return found[0]
        default: return found[try prompts.askChoice("Which Settings.bundle?", options: found)]
        }
    }

    private func prepareSettingsBundle(at bundle: String, root: String) throws(DomainError) {
        let plistPath = bundle + "/Root.plist"
        let original: Data? =
            files.exists(at: plistPath)
            ? try files.readRegularFile(at: try files.realPath(of: plistPath), upToBytes: 4_194_304)
            : nil
        let edit = try RootPlistEditor.edited(original)
        if edit.change != .unchanged {
            try writer.createDirectory(at: bundle)
            if let original {
                try writer.createDirectory(at: root + "/.dependi")
                try writer.write(original, toPath: root + "/.dependi/Root.plist.bak")
            }
            try writer.write(edit.data, toPath: plistPath)
        }
        switch edit.change {
        case .unchanged:
            output.writeLine("Dependi: Root.plist already has the Acknowledgements pane.")
        case .added: output.writeLine("Dependi: added the Acknowledgements pane to \(plistPath).")
        case .rewroteOldEntry:
            output.writeLine(
                "Dependi: changed the old LicensePlist pane in \(plistPath) to Acknowledgements. The old file is saved as .dependi/Root.plist.bak, outside the bundle so it does not ship."
            )
        }
        if original == nil {
            output.writeLine("Dependi: add \(bundle) to your app target as a resource in Xcode.")
        }
        try removeClashes(in: bundle)
    }

    private func removeClashes(in bundle: String) throws(DomainError) {
        guard let names = try? directories.topLevelNames(in: bundle) else { return }
        for name in Self.clashingNames where names.contains(name) {
            output.writeLine(
                "Dependi: \(bundle)/\(name) would clash with the files Dependi writes into the app."
            )
            if try prompts.askConfirmation("Remove \(name) from the source Settings.bundle?") {
                try writer.removeItem(at: bundle + "/" + name)
                output.writeLine("Dependi: removed \(name).")
            } else {
                output.writeLine("Dependi: kept \(name). The build will fail until it is removed.")
            }
        }
    }

    // MARK: Tool files

    private func installTool(in root: String) throws(DomainError) {
        try writer.createDirectory(at: root + "/.dependi/bin")
        let real = try files.realPath(of: executablePath)
        let binary = try files.readRegularFile(at: real, upToBytes: Self.maximumExecutableBytes)
        if binary.count > Self.maximumExecutableBytes {
            throw .initRefused(
                reason: "the Dependi program is larger than \(Self.maximumExecutableBytes) bytes.")
        }
        try writer.write(binary, toPath: root + "/.dependi/bin/dependi")
        try executables.makeExecutable(at: root + "/.dependi/bin/dependi")
        try writer.write(Data((version + "\n").utf8), toPath: root + "/.dependi/bin/VERSION")
        try writer.write(Data(wrapperText.utf8), toPath: root + "/.dependi/run.sh")
        try executables.makeExecutable(at: root + "/.dependi/run.sh")
        let inputs = [
            "$(SRCROOT)/.dependi.json", "$(SRCROOT)/.dependi/run.sh",
            "$(SRCROOT)/.dependi/bin/VERSION",
            "$(PROJECT_FILE_PATH)/project.pbxproj",
            "$(PROJECT_FILE_PATH)/project.xcworkspace/xcshareddata/swiftpm/Package.resolved",
        ]
        try writer.write(
            Data((inputs.joined(separator: "\n") + "\n").utf8),
            toPath: root + "/.dependi/inputs.xcfilelist")
        output.writeLine(
            "Dependi: installed .dependi/bin/dependi \(version), run.sh and inputs.xcfilelist.")
    }

    private func updateIgnoreFile(in root: String) throws(DomainError) {
        let path = root + "/.gitignore"
        let rule = ".dependi/bin/"
        var text = ""
        if files.exists(at: path) {
            let data = try files.readRegularFile(
                at: try files.realPath(of: path), upToBytes: 1_048_576)
            text = String(decoding: data, as: UTF8.self)
        }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        if lines.contains(rule) { return }
        if !text.isEmpty && !text.hasSuffix("\n") { text += "\n" }
        try writer.write(Data((text + rule + "\n").utf8), toPath: path)
        output.writeLine("Dependi: added \(rule) to .gitignore.")
    }

    private func printRunScript(root: String) {
        output.writeLine("")
        output.writeLine(
            "Add a Run Script build phase to the app target, after Copy Bundle Resources:")
        output.writeLine("    \"${SRCROOT}/.dependi/run.sh\" generate")
        output.writeLine("In that phase:")
        output.writeLine(
            "    1. Add the input file list $(SRCROOT)/.dependi/inputs.xcfilelist and keep Based on dependency analysis on."
        )
        output.writeLine(
            "    2. Add the output file $(TARGET_BUILD_DIR)/$(UNLOCALIZED_RESOURCES_FOLDER_PATH)/Settings.bundle/Acknowledgements.plist"
        )
        output.writeLine(
            "    3. Set ENABLE_USER_SCRIPT_SANDBOXING to NO for the target (a script-only target for Dependi is best)."
        )
        output.writeLine(
            "Commit .dependi.json and .dependi/run.sh. The program in .dependi/bin is ignored by git and rebuilt by the script."
        )
    }
}
