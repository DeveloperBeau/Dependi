import DependiComposition
import DependiDomain
import DependiInit
import Foundation
import Testing

@Suite("End to end")
struct EndToEndTests {
    /// An app that links Alamofire, which depends on swift-log.
    private func standardWorld() throws -> EndToEndWorld {
        let world = try EndToEndWorld()
        try world.addRemote(
            "alamofire", owner: "Alamofire",
            manifest: EndToEndWorld.manifest(
                product: "Alamofire", dependencies: ["Logging"], declared: ["swift-log"]))
        try world.addRemote(
            "swift-log", owner: "apple", manifest: EndToEndWorld.manifest(product: "Logging"))
        return world
    }

    private func childPane(_ world: EndToEndWorld, slug: String) throws -> [String: Any] {
        try world.plist("Acknowledgements/\(slug).plist")
    }

    // MARK: Archive

    @Test("an archive writes the direct and the transitive package with their license text")
    func archiveWritesDirectAndTransitive() throws {
        let world = try standardWorld()
        let result = try world.run()
        #expect(result.code == 0, "errors: \(result.errors)")
        #expect(try world.indexTitles() == ["alamofire", "swift-log"])
        let index = try world.plist("Acknowledgements.plist")
        #expect(index["Title"] as? String == "Acknowledgements")
        let entries = try requireValue(index["PreferenceSpecifiers"] as? [[String: String]])
        #expect(
            entries.map { $0["File"] } == [
                "Acknowledgements/alamofire-5f720a3f84a5",
                "Acknowledgements/swift-log-8051385eb569",
            ])
        #expect(entries.allSatisfy { $0["Type"] == "PSChildPaneSpecifier" })
        let pane = try childPane(world, slug: "alamofire-5f720a3f84a5")
        let groups = try requireValue(pane["PreferenceSpecifiers"] as? [[String: String]])
        #expect(
            groups == [
                [
                    "Type": "PSGroupSpecifier", "Title": "LICENSE",
                    "FooterText": "license of alamofire",
                ]
            ])
        let logPane = try childPane(world, slug: "swift-log-8051385eb569")
        #expect(
            (logPane["PreferenceSpecifiers"] as? [[String: String]])?.first?["FooterText"]
                == "license of swift-log")
        #expect(
            world.files(in: "Acknowledgements") == [
                ".dependi-manifest", "alamofire-5f720a3f84a5.plist", "swift-log-8051385eb569.plist",
            ])
        #expect(result.output.contains("Dependi: wrote 2 acknowledgements"))
    }

    @Test("the process requests use the clean environment and the resolved toolchain")
    func processRequestsAreClean() throws {
        let world = try standardWorld()
        _ = try world.run()
        let requests = world.runner.requests
        #expect(requests.first?.executable == "/usr/bin/xcrun")
        #expect(requests.first?.arguments == ["--find", "swift"])
        for request in requests {
            #expect(request.environment["SDKROOT"] == nil)
            #expect(request.environment["PATH"] == "/usr/bin:/bin")
            #expect(request.arguments.contains("--disable-sandbox") == false)
        }
        let dumps = requests.dropFirst()
        #expect(dumps.count == 2)
        #expect(
            dumps.allSatisfy {
                $0.executable == "/toolchain/usr/bin/swift" && $0.arguments.last == "dump-package"
            })
    }

    @Test("a second run gives identical bytes and changes no modification time")
    func idempotentRun() throws {
        let world = try standardWorld()
        _ = try world.run()
        func snapshot() throws -> [String: (Data, Date)] {
            var result: [String: (Data, Date)] = [:]
            for name in ["Acknowledgements.plist"]
                + world.files(in: "Acknowledgements").map({ "Acknowledgements/\($0)" })
            {
                let path = world.bundle + "/" + name
                let attributes = try FileManager.default.attributesOfItem(atPath: path)
                result[name] = (
                    try Data(contentsOf: URL(fileURLWithPath: path)),
                    try requireValue(attributes[.modificationDate] as? Date)
                )
            }
            return result
        }
        let first = try snapshot()
        Thread.sleep(forTimeInterval: 1.1)
        let second = try world.run()
        #expect(second.code == 0)
        let again = try snapshot()
        #expect(Set(first.keys) == Set(again.keys))
        for (name, value) in first {
            #expect(value.0 == again[name]?.0, "bytes of \(name)")
            #expect(value.1 == again[name]?.1, "modification time of \(name)")
        }
    }

    @Test("a dependency that is dropped between runs loses its pane")
    func droppedDependencyRemovesPane() throws {
        let world = try standardWorld()
        _ = try world.run()
        #expect(world.files(in: "Acknowledgements").contains("swift-log-8051385eb569.plist"))
        try world.removeRemote("swift-log")
        world.runner.dumps["alamofire"] = EndToEndWorld.manifest(product: "Alamofire")
        try "// changed manifest".write(
            toFile: world.sourcePackages + "/checkouts/alamofire/Package.swift", atomically: true,
            encoding: .utf8)
        let result = try world.run()
        #expect(result.code == 0, "errors: \(result.errors)")
        #expect(
            world.files(in: "Acknowledgements") == [
                ".dependi-manifest", "alamofire-5f720a3f84a5.plist",
            ])
        #expect(try world.indexTitles() == ["alamofire"])
    }

    @Test("a Mac Catalyst product writes into its resources folder")
    func catalystResources() throws {
        let world = try standardWorld()
        try FileManager.default.createDirectory(
            atPath: world.products + "/App.app/Contents/Resources",
            withIntermediateDirectories: true)
        world.environment["UNLOCALIZED_RESOURCES_FOLDER_PATH"] = "App.app/Contents/Resources"
        let result = try world.run()
        #expect(result.code == 0, "errors: \(result.errors)")
        #expect(
            FileManager.default.fileExists(
                atPath: world.products
                    + "/App.app/Contents/Resources/Settings.bundle/Acknowledgements.plist"))
    }

    @Test("a configuration in the gate list runs on a build action")
    func customConfiguration() throws {
        let world = try EndToEndWorld(configuration: #"{"gateConfigurations":["AppStore"]}"#)
        try world.addRemote("alamofire", owner: "Alamofire")
        world.environment["ACTION"] = "build"
        world.environment["CONFIGURATION"] = "AppStore"
        let result = try world.run()
        #expect(result.code == 0, "errors: \(result.errors)")
        #expect(try world.indexTitles() == ["alamofire"])
    }

    // MARK: Skips

    @Test("a Debug build skips with no process, no bundle and exit code zero")
    func debugSkips() throws {
        let world = try standardWorld()
        world.environment["ACTION"] = "build"
        world.environment["CONFIGURATION"] = "Debug"
        let result = try world.run()
        #expect(result.code == 0)
        #expect(world.runner.requests.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: world.bundle))
        #expect(
            result.output.contains("Dependi: skipped. configuration Debug is not in the gate list"))
    }

    // MARK: Failures

    @Test("a package without a license fails the run, names the package and writes nothing")
    func missingLicense() throws {
        let world = try EndToEndWorld()
        try world.addRemote("alamofire", owner: "Alamofire", license: nil)
        let result = try world.run()
        #expect(result.code == 1)
        #expect(result.errors.contains("The package alamofire has no license file."))
        #expect(!FileManager.default.fileExists(atPath: world.bundle))
    }

    @Test("a resolved package that no product reaches fails and is listed")
    func unreachedPackage() throws {
        let world = try standardWorld()
        try world.addRemote("spare", owner: "someone")
        let result = try world.run()
        #expect(result.code == 1)
        #expect(result.errors.contains("These resolved packages are not linked by the app: spare."))
    }

    @Test("a missing configuration fails an archive and names the file")
    func missingConfigurationOnArchive() throws {
        let world = try EndToEndWorld(configuration: nil)
        try world.addRemote("alamofire", owner: "Alamofire")
        let result = try world.run()
        #expect(result.code == 1)
        #expect(result.errors.contains(".dependi.json"))
    }

    @Test("the script sandbox being on fails with the setting to change")
    func sandboxOn() throws {
        let world = try standardWorld()
        world.environment["ENABLE_USER_SCRIPT_SANDBOXING"] = "YES"
        let result = try world.run()
        #expect(result.code == 1)
        #expect(result.errors.contains("ENABLE_USER_SCRIPT_SANDBOXING"))
    }

    @Test("a pinned revision that differs from the checkout fails")
    func pinnedRevisionMismatch() throws {
        let world = try EndToEndWorld()
        try world.addRemote("alamofire", owner: "Alamofire", revision: "r1")
        let resolved =
            #"{"version":2,"pins":[{"identity":"alamofire","kind":"remoteSourceControl","location":"https://github.com/Alamofire/Alamofire.git","state":{"revision":"other","version":"1.0.0"}}]}"#
        try FileManager.default.createDirectory(
            atPath: world.project + "/App.xcodeproj/project.xcworkspace/xcshareddata/swiftpm",
            withIntermediateDirectories: true)
        try resolved.write(
            toFile: world.project
                + "/App.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved",
            atomically: true, encoding: .utf8)
        let result = try world.run()
        #expect(result.code == 1)
        #expect(result.errors.contains("checked out at r1 but Package.resolved pins other"))
    }

    // MARK: Graph rules through the real readers

    private func macroManifest() -> String {
        EndToEndWorld.manifest(
            product: "Alamofire", dependencies: [], declared: ["swift-syntax"],
            kinds: [("AlamofireMacros", "macro", ["SwiftSyntax"])]
        ).replacingOccurrences(
            of: "\"type\":\"regular\",\"dependencies\":[]",
            with: "\"type\":\"regular\",\"dependencies\":[{\"target\":[\"AlamofireMacros\",null]}]"
        )
        .replacingOccurrences(
            of: "[\"SwiftSyntax\",\"SwiftSyntax\"", with: "[\"SwiftSyntax\",\"swift-syntax\"")
    }

    @Test("the dependencies of a macro target are left out unless build tools are included")
    func macroDependencies() throws {
        let world = try EndToEndWorld(configuration: #"{"allowUnreached":true}"#)
        try world.addRemote("alamofire", owner: "Alamofire", manifest: macroManifest())
        try world.addRemote(
            "swift-syntax", owner: "swiftlang",
            manifest: EndToEndWorld.manifest(product: "SwiftSyntax"))
        #expect(try world.run().code == 0)
        #expect(try world.indexTitles() == ["alamofire"])

        let withTools = try EndToEndWorld(configuration: #"{"includeBuildTools":true}"#)
        try withTools.addRemote("alamofire", owner: "Alamofire", manifest: macroManifest())
        try withTools.addRemote(
            "swift-syntax", owner: "swiftlang",
            manifest: EndToEndWorld.manifest(product: "SwiftSyntax"))
        #expect(try withTools.run().code == 0)
        #expect(try withTools.indexTitles() == ["alamofire", "swift-syntax"])
    }

    @Test("a local package of the project file is written")
    func localPackage() throws {
        let project = EndToEndWorld.alamofireProject
            .replacingOccurrences(
                of:
                    "R1 = {isa = XCRemoteSwiftPackageReference; repositoryURL = \"https://github.com/Alamofire/Alamofire.git\"; };",
                with: "R1 = {isa = XCLocalSwiftPackageReference; relativePath = Packages/Core; };"
            )
            .replacingOccurrences(
                of:
                    "D1 = {isa = XCSwiftPackageProductDependency; package = R1; productName = Alamofire; };",
                with: "D1 = {isa = XCSwiftPackageProductDependency; productName = Core; };")
        let world = try EndToEndWorld(projectFile: project)
        try world.addLocal("Core", manifest: EndToEndWorld.manifest(product: "Core"))
        let result = try world.run()
        #expect(result.code == 0, "errors: \(result.errors)")
        #expect(try world.indexTitles() == ["core"])
    }

    @Test("only the products of the named target are written")
    func twoTargets() throws {
        let twoTargets = EndToEndWorld.alamofireProject
            .replacingOccurrences(of: "targets = (T1);", with: "targets = (T1, T2);")
            .replacingOccurrences(
                of: "\t\tT1L = ",
                with:
                    "\t\tD2 = {isa = XCSwiftPackageProductDependency; package = R2; productName = Logging; };\n\t\tR2 = {isa = XCRemoteSwiftPackageReference; repositoryURL = \"https://github.com/apple/swift-log.git\"; };\n\t\tT2 = {isa = PBXNativeTarget; name = Other; productType = \"com.apple.product-type.application\"; dependencies = (); packageProductDependencies = (D2); buildPhases = (); buildConfigurationList = T1L; };\n\t\tT1L = "
            )
            .replacingOccurrences(
                of: "packageReferences = (R1);", with: "packageReferences = (R1, R2);")
        let world = try EndToEndWorld(
            configuration: #"{"allowUnreached":true}"#, projectFile: twoTargets)
        try world.addRemote("alamofire", owner: "Alamofire")
        try world.addRemote(
            "swift-log", owner: "apple", manifest: EndToEndWorld.manifest(product: "Logging"))
        #expect(try world.run().code == 0)
        #expect(try world.indexTitles() == ["alamofire"])
        world.environment["TARGET_NAME"] = "Other"
        #expect(try world.run().code == 0)
        #expect(try world.indexTitles() == ["swift-log"])
    }

    // MARK: Command line

    @Test("the version and help commands print and succeed")
    func versionAndHelp() throws {
        let world = try EndToEndWorld()
        let version = try world.run(["--version"])
        #expect(version.code == 0)
        #expect(version.output == "dependi \(DependiVersion.current)\n")
        let help = try world.run(["help"])
        #expect(help.code == 0)
        #expect(help.output.contains("generate"))
        #expect(world.runner.requests.isEmpty)
    }

    @Test(
        "a command line error exits with 64 and prints the usage",
        arguments: [[], ["frobnicate"], ["generate", "--x"], ["init"]])
    func commandLineErrors(arguments: [String]) throws {
        let world = try EndToEndWorld()
        let result = try world.run(arguments)
        #expect(result.code == DependiApplication.usageExitCode)
        #expect(result.errors.contains("error:"))
        #expect(result.errors.contains("generate"))
    }

    // MARK: Init

    private func initWorld() throws -> EndToEndWorld {
        let world = try EndToEndWorld(configuration: nil)
        try world.addRemote(
            "alamofire", owner: "Alamofire",
            manifest: EndToEndWorld.manifest(
                product: "Alamofire", dependencies: ["Logging"], declared: ["swift-log"]))
        try world.addRemote(
            "swift-log", owner: "apple", manifest: EndToEndWorld.manifest(product: "Logging"))
        try "BINARY".write(
            toFile: world.root.path + "/dependi-bin", atomically: true, encoding: .utf8)
        return world
    }

    @Test("init installs the files and the configuration it writes is read by generate")
    func initThenGenerate() throws {
        let world = try initWorld()
        let installed = try world.run(["init", "--project", world.project])
        #expect(installed.code == 0, "errors: \(installed.errors)")
        #expect(FileManager.default.fileExists(atPath: world.project + "/.dependi.json"))
        #expect(
            try String(contentsOfFile: world.project + "/.dependi/run.sh", encoding: .utf8)
                == WrapperScript.text)
        #expect(
            try String(contentsOfFile: world.project + "/.dependi/bin/dependi", encoding: .utf8)
                == "BINARY")
        #expect(
            FileManager.default.isExecutableFile(atPath: world.project + "/.dependi/bin/dependi"))
        #expect(FileManager.default.isExecutableFile(atPath: world.project + "/.dependi/run.sh"))
        #expect(
            try String(contentsOfFile: world.project + "/.dependi/bin/VERSION", encoding: .utf8)
                == "\(DependiVersion.current)\n")
        #expect(
            try String(contentsOfFile: world.project + "/.gitignore", encoding: .utf8)
                == ".dependi/bin/\n")
        #expect(installed.output.contains("\"${SRCROOT}/.dependi/run.sh\" generate"))

        let generated = try world.run(["generate"])
        #expect(generated.code == 0, "errors: \(generated.errors)")
        #expect(try world.indexTitles() == ["alamofire", "swift-log"])
    }

    @Test("a relative project path is resolved against the current folder")
    func relativeInitPath() throws {
        let world = try initWorld()
        let result = try world.run(["init", "--project", "proj"])
        #expect(result.code == 0, "errors: \(result.errors)")
        #expect(FileManager.default.fileExists(atPath: world.project + "/.dependi.json"))
    }

    @Test("a dry run writes nothing")
    func initDryRun() throws {
        let world = try initWorld()
        let result = try world.run(["init", "--project", world.project, "--dry-run"])
        #expect(result.code == 0)
        #expect(!FileManager.default.fileExists(atPath: world.project + "/.dependi.json"))
        #expect(!FileManager.default.fileExists(atPath: world.project + "/.dependi"))
        #expect(result.output.contains("Dry run. Nothing is changed."))
    }

    @Test("a project that does not exist fails with the path in the message")
    func initMissingProject() throws {
        let world = try initWorld()
        let result = try world.run(["init", "--project", world.root.path + "/nowhere"])
        #expect(result.code == 1)
        #expect(result.errors.contains("There is no Xcode project at"))
    }
}
