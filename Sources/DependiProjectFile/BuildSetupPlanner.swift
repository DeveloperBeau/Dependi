import DependiDomain
import Foundation

/// Works out the text edits that make one app target ready for the Dependi build step.
///
/// The model answers what the project means. The scanner answers where the text is.
struct BuildSetupPlanner {
    private static let settingKey = "ENABLE_USER_SCRIPT_SANDBOXING"
    private static let shellSection = "PBXShellScriptBuildPhase"

    private let model: ProjectModel
    private let scanner: PBXTextScanner
    private let resolver: ReferencePathResolver
    private var ids: ProjectObjectIDMaker
    private var plan = BuildSetupPlan()

    /// Creates a planner for one parsed project and the scan of its text.
    init(model: ProjectModel, scanner: PBXTextScanner, ids: ProjectObjectIDMaker) {
        self.model = model
        self.scanner = scanner
        self.resolver = ReferencePathResolver(model: model)
        self.ids = ids
    }

    /// Plans the edits for a target. The bundle path is absolute and inside the project folder.
    mutating func plan(targetName: String, bundlePath: String) throws(DomainError) -> BuildSetupPlan
    {
        plan = BuildSetupPlan()
        let targets = try model.nativeTargets()
        guard let target = targets.first(where: { $0.name == targetName }),
            let object = model.object(target.id, isa: "PBXNativeTarget")
        else {
            let names = targets.map(\.name).sorted().joined(separator: ", ")
            throw .fileUnreadable(
                path: model.path,
                reason: "there is no target named \(targetName). Available targets: \(names)")
        }
        let bundle = ProjectPathMath.standardize(bundlePath)
        let prefix = model.folder == "/" ? "/" : model.folder + "/"
        guard bundle.hasPrefix(prefix), bundle.hasSuffix("/Settings.bundle") else {
            throw .initRefused(
                reason: "the Settings.bundle at \(bundlePath) is not inside the project folder")
        }
        let relative = String(bundle.dropFirst(prefix.count))
        let phases = try model.strings(object, "buildPhases")
        let resourcePhases = phases.enumerated().compactMap { index, id in
            model.object(id, isa: "PBXResourcesBuildPhase").map { (index, id, $0) }
        }
        guard let resources = resourcePhases.first else {
            throw .initRefused(
                reason:
                    "\(targetName) has no Copy Bundle Resources phase. Add one in Xcode, then run again."
            )
        }
        guard resourcePhases.count == 1 else {
            throw .initRefused(
                reason:
                    "\(targetName) has more than one Copy Bundle Resources phase. Merge them in Xcode, then run again."
            )
        }
        try planBundle(
            target: target, object: object, resources: (resources.1, resources.2),
            bundle: bundle, relative: relative)
        try planPhase(
            target: target, phases: phases, resourcesID: resources.1, resourcesIndex: resources.0)
        try planSandboxSetting(target: target, object: object)
        return plan
    }

    private mutating func newID(
        target: (id: String, name: String), role: String
    ) throws(DomainError) -> String {
        guard let id = ids.make(targetID: target.id, role: role) else {
            throw .unsafeProject(
                path: model.path,
                why: "no free object id was found for the \(role) of \(target.name)")
        }
        return id
    }

    // MARK: Settings.bundle

    private mutating func planBundle(
        target: (id: String, name: String), object: ProjectModel.Object,
        resources: (id: String, object: ProjectModel.Object), bundle: String, relative: String
    ) throws(DomainError) {
        let resourcesID = resources.id
        for fileID in try model.strings(resources.object, "files") {
            // A build file with no file reference, such as `(null) in Resources`, is not a bundle.
            guard let file = model.object(fileID, isa: "PBXBuildFile"),
                let referenceID = file["fileRef"] as? String,
                let reference = model.object(referenceID, isa: "PBXFileReference"),
                isSettingsBundle(reference)
            else { continue }
            if resolver.location(of: referenceID) == bundle { return }
            throw .initRefused(
                reason:
                    "\(target.name) already copies another Settings.bundle. Remove it in Xcode, then run again."
            )
        }
        if try isCoveredBySynchronizedGroup(target: target, object: object, bundle: bundle) {
            return
        }
        let referenceID: String
        if let existing = existingReference(at: bundle) {
            referenceID = existing
        } else {
            referenceID = try newID(target: target, role: "fileReference")
            try addFileReference(id: referenceID, relative: relative)
        }
        let buildFileID = try newID(target: target, role: "buildFile")
        try insertSectionLine(
            "\t\t\(buildFileID) /* Settings.bundle in Resources */ = {isa = PBXBuildFile; fileRef = \(referenceID) /* Settings.bundle */; };\n",
            id: buildFileID, isa: "PBXBuildFile")
        try insertListLine(
            "\(buildFileID) /* Settings.bundle in Resources */", objectID: resourcesID,
            key: "files",
            after: nil)
        plan.addedIDs.insert(buildFileID)
        plan.editedIDs.insert(resourcesID)
        plan.lines.append(
            "Dependi: added Settings.bundle to Copy Bundle Resources of \(target.name).")
    }

    private func isSettingsBundle(_ reference: ProjectModel.Object) -> Bool {
        guard reference["lastKnownFileType"] as? String != "folder" else { return false }
        let name =
            reference["name"] as? String
            ?? (reference["path"] as? String)?.split(separator: "/").last.map(String.init)
        return name == "Settings.bundle"
    }

    /// The first reference in file order that already points to the bundle.
    private func existingReference(at bundle: String) -> String? {
        model.objects.keys
            .filter {
                model.object($0, isa: "PBXFileReference").map(isSettingsBundle) == true
                    && resolver.location(of: $0) == bundle
            }
            .compactMap { id in scanner.object(id).map { (id: id, index: $0.keyIndex) } }
            .min { $0.index < $1.index }?.id
    }

    /// Whether a synchronized folder of the target already copies the bundle.
    private func isCoveredBySynchronizedGroup(
        target: (id: String, name: String), object: ProjectModel.Object, bundle: String
    ) throws(DomainError) -> Bool {
        for groupID in try model.strings(object, "fileSystemSynchronizedGroups") {
            guard let group = model.object(groupID, isa: "PBXFileSystemSynchronizedRootGroup"),
                let folder = resolver.location(of: groupID), bundle.hasPrefix(folder + "/")
            else { continue }
            let inside = String(bundle.dropFirst(folder.count + 1))
            for exceptionID in try model.strings(group, "exceptions") {
                guard
                    let set = model.object(
                        exceptionID, isa: "PBXFileSystemSynchronizedBuildFileExceptionSet"),
                    set["target"] as? String == target.id
                else { continue }
                if try model.strings(set, "membershipExceptions").contains(inside) {
                    throw .initRefused(
                        reason:
                            "the folder \(folder) leaves Settings.bundle out of \(target.name). Add it in Xcode, then run again."
                    )
                }
            }
            return true
        }
        return false
    }

    private mutating func addFileReference(id: String, relative: String) throws(DomainError) {
        // Xcode writes `name` only when the path has a folder.
        let name = relative.contains("/") ? "name = Settings.bundle; " : ""
        try insertSectionLine(
            "\t\t\(id) /* Settings.bundle */ = {isa = PBXFileReference; lastKnownFileType = \"wrapper.plug-in\"; \(name)path = \(Self.quoted(relative)); sourceTree = SOURCE_ROOT; };\n",
            id: id, isa: "PBXFileReference")
        guard let mainGroup = model.project["mainGroup"] as? String,
            model.object(mainGroup, isa: "PBXGroup") != nil
        else { throw .unsafeProject(path: model.path, why: "the main group is missing") }
        try insertListLine(
            "\(id) /* Settings.bundle */", objectID: mainGroup, key: "children", after: nil)
        plan.addedIDs.insert(id)
        plan.editedIDs.insert(mainGroup)
        plan.lines.append(
            "Dependi: added the file reference Settings.bundle (\(relative)) to the main group.")
    }

    /// Writes a value the way Xcode does: bare when it is plain, otherwise quoted.
    static func quoted(_ value: String) -> String {
        let plain =
            !value.isEmpty
            && value.utf8.allSatisfy {
                ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x41 && $0 <= 0x5A)
                    || ($0 >= 0x61 && $0 <= 0x7A)
                    || $0 == 0x5F || $0 == 0x2E || $0 == 0x2F
            }
        guard !plain else { return value }
        let escaped = value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    // MARK: Run Script phase

    private mutating func planPhase(
        target: (id: String, name: String), phases: [String], resourcesID: String,
        resourcesIndex: Int
    ) throws(DomainError) {
        for (index, id) in phases.enumerated() {
            guard let phase = model.object(id, isa: Self.shellSection),
                (phase["shellScript"] as? String)?.contains(".dependi/run.sh") == true
            else { continue }
            if index < resourcesIndex {
                plan.lines.append(
                    "Dependi: the Dependi Run Script phase of \(target.name) runs before Copy Bundle Resources. Move it below that phase in Xcode."
                )
            }
            return
        }
        let id = try newID(target: target, role: "scriptPhase")
        try insertShellPhase(id: id)
        try insertListLine(
            "\(id) /* Dependi */", objectID: target.id, key: "buildPhases", after: resourcesID)
        plan.addedIDs.insert(id)
        plan.editedIDs.insert(target.id)
        plan.lines.append(
            "Dependi: added the Dependi Run Script phase after Copy Bundle Resources of \(target.name)."
        )
    }

    private mutating func insertShellPhase(id: String) throws(DomainError) {
        let entry = """
            \t\t\(id) /* Dependi */ = {
            \t\t\tisa = PBXShellScriptBuildPhase;
            \t\t\tbuildActionMask = 2147483647;
            \t\t\tfiles = (
            \t\t\t);
            \t\t\tinputFileListPaths = (
            \t\t\t\t"$(SRCROOT)/.dependi/inputs.xcfilelist",
            \t\t\t);
            \t\t\tinputPaths = (
            \t\t\t);
            \t\t\tname = Dependi;
            \t\t\toutputFileListPaths = (
            \t\t\t);
            \t\t\toutputPaths = (
            \t\t\t\t"$(TARGET_BUILD_DIR)/$(UNLOCALIZED_RESOURCES_FOLDER_PATH)/Settings.bundle/Acknowledgements.plist",
            \t\t\t);
            \t\t\trunOnlyForDeploymentPostprocessing = 0;
            \t\t\tshellPath = /bin/sh;
            \t\t\tshellScript = "\\"${SRCROOT}/.dependi/run.sh\\" generate\\n";
            \t\t};

            """
        let sections = scanner.sections()
        if sections.contains(where: { $0.isa == Self.shellSection }) {
            try insertSectionLine(entry, id: id, isa: Self.shellSection)
            return
        }
        let block =
            "/* Begin \(Self.shellSection) section */\n" + entry
            + "/* End \(Self.shellSection) section */\n"
        if let next = sections.first(where: { $0.isa > Self.shellSection }) {
            plan.edits.append(
                PBXTextEdit(offset: next.begin, removeCount: 0, insertText: block + "\n"))
        } else if let last = sections.last {
            plan.edits.append(
                PBXTextEdit(
                    offset: scanner.lineEnd(of: last.end), removeCount: 0, insertText: "\n" + block)
            )
        } else {
            throw .unsafeProject(path: model.path, why: "the section markers are missing")
        }
    }

    // MARK: Sandbox setting

    private mutating func planSandboxSetting(
        target: (id: String, name: String), object: ProjectModel.Object
    ) throws(DomainError) {
        guard let listID = object["buildConfigurationList"] as? String,
            let list = model.object(listID, isa: "XCConfigurationList")
        else { return }
        var overridesFile = false
        for configID in try model.strings(list, "buildConfigurations") {
            guard let configuration = model.object(configID, isa: "XCBuildConfiguration"),
                let body = scanner.object(configID),
                let settings = try scanner.entry("buildSettings", inDictionaryAt: body.valueFirst),
                scanner.close(of: settings.valueFirst) != nil
            else {
                throw .unsafeProject(path: model.path, why: "a build configuration was not found")
            }
            let name = configuration["name"] as? String ?? configID
            let entries = try scanner.entries(ofDictionaryAt: settings.valueFirst)
            // A conditional key can still win over the plain one, so it is never edited around.
            if let conditional = entries.first(where: { $0.key.hasPrefix(Self.settingKey + "[") }) {
                throw .unsafeProject(
                    path: model.path,
                    why:
                        "the \(name) configuration of \(target.name) sets the conditional key \(conditional.key). Remove it in Xcode, then run again"
                )
            }
            if let existing = entries.first(where: { $0.key == Self.settingKey }) {
                if existing.valueFirst == existing.valueLast,
                    scanner.text(existing.valueFirst) == "NO"
                {
                    continue
                }
                let range =
                    scanner.spans[existing.valueFirst].range
                    .lowerBound..<scanner.spans[existing.valueLast].range.upperBound
                let old =
                    existing.valueFirst == existing.valueLast
                    ? scanner.text(existing.valueFirst) : "a list"
                plan.edits.append(
                    PBXTextEdit(
                        offset: range.lowerBound, removeCount: range.count, insertText: "NO"))
                plan.lines.append(
                    "Dependi: set \(Self.settingKey) = NO in \(name) of \(target.name) (was \(old))."
                )
            } else {
                try insertSetting(entries: entries, dictionary: settings)
                plan.lines.append(
                    "Dependi: set \(Self.settingKey) = NO in \(name) of \(target.name).")
                if configuration["baseConfigurationReference"] != nil
                    || configuration["baseConfigurationReferenceAnchor"] != nil
                {
                    overridesFile = true
                }
            }
            plan.editedIDs.insert(configID)
        }
        if overridesFile {
            plan.lines.append(
                "Dependi: the value in the xcconfig file is now overridden for \(target.name).")
        }
    }

    private mutating func insertSetting(
        entries: [PBXTextScanner.Entry], dictionary: PBXTextScanner.Entry
    ) throws(DomainError) {
        let line = "\(Self.settingKey) = NO;\n"
        if let next = entries.first(where: { Self.sortsAfter($0.key, Self.settingKey) }) {
            guard let indent = scanner.tabsBefore(span: next.keyIndex) else {
                throw .unsafeProject(
                    path: model.path, why: "a build setting is not on its own line")
            }
            plan.edits.append(
                PBXTextEdit(
                    offset: scanner.lineStart(of: scanner.spans[next.keyIndex].range.lowerBound),
                    removeCount: 0, insertText: indent + line))
            return
        }
        guard let close = scanner.close(of: dictionary.valueFirst),
            let indent = scanner.tabsBefore(span: close)
        else {
            throw .unsafeProject(
                path: model.path, why: "the build settings are not laid out in lines")
        }
        plan.edits.append(
            PBXTextEdit(
                offset: scanner.lineStart(of: scanner.spans[close].range.lowerBound),
                removeCount: 0, insertText: indent + "\t" + line))
    }

    /// Whether a key sorts after another in byte order, which is how Xcode orders build settings.
    private static func sortsAfter(_ key: String, _ other: String) -> Bool {
        other.utf8.lexicographicallyPrecedes(key.utf8)
    }

    // MARK: Text insertion

    /// Adds a whole line to a section, before the first entry whose id sorts after `id`.
    private mutating func insertSectionLine(_ text: String, id: String, isa: String)
        throws(DomainError)
    {
        guard let section = scanner.sections().first(where: { $0.isa == isa }) else {
            throw .unsafeProject(path: model.path, why: "the \(isa) section markers are missing")
        }
        var offset = scanner.lineEnd(of: section.begin)
        while offset < section.end {
            let bytes = scanner.bytes
            let isEntry =
                offset + 2 < bytes.count && bytes[offset] == 9 && bytes[offset + 1] == 9
                && bytes[offset + 2] != 9 && bytes[offset + 2] != 0x7D && bytes[offset + 2] != 0x20
            if isEntry {
                let entryID = bytes[(offset + 2)...].prefix { $0 != 0x20 }
                if Self.sortsAfter(String(decoding: entryID, as: UTF8.self), id) { break }
            }
            offset = scanner.lineEnd(of: offset)
        }
        plan.edits.append(PBXTextEdit(offset: offset, removeCount: 0, insertText: text))
    }

    /// Adds a line to a list of an object, after one item or at the end.
    private mutating func insertListLine(
        _ item: String, objectID: String, key: String, after previous: String?
    ) throws(DomainError) {
        guard let object = scanner.object(objectID),
            let entry = try scanner.entry(key, inDictionaryAt: object.valueFirst),
            let close = scanner.close(of: entry.valueFirst)
        else { throw .unsafeProject(path: model.path, why: "the list \(key) was not found") }
        let starts = try scanner.itemStarts(ofListAt: entry.valueFirst)
        let anchor =
            previous.flatMap { id in starts.first { scanner.text($0) == id } } ?? starts.last
        if let anchor {
            guard let indent = scanner.tabsBefore(span: anchor),
                scanner.lineStart(of: scanner.spans[anchor + 1].range.lowerBound)
                    == scanner.lineStart(of: scanner.spans[anchor].range.lowerBound)
            else { throw .unsafeProject(path: model.path, why: "a list is not laid out in lines") }
            plan.edits.append(
                PBXTextEdit(
                    offset: scanner.lineEnd(of: scanner.spans[anchor + 1].range.lowerBound),
                    removeCount: 0, insertText: "\(indent)\(item),\n"))
            return
        }
        guard let indent = scanner.tabsBefore(span: close) else {
            throw .unsafeProject(path: model.path, why: "a list is not laid out in lines")
        }
        plan.edits.append(
            PBXTextEdit(
                offset: scanner.lineStart(of: scanner.spans[close].range.lowerBound),
                removeCount: 0,
                insertText: "\(indent)\t\(item),\n"))
    }
}
