import DependiDomain
import Foundation
import Testing

@testable import DependiProjectFile

/// One test for each refusal of the editor. Each input is written by hand and breaks one rule only.
@Suite("Project file editor guards", .timeLimit(.minutes(1)))
struct BuildEditGuardTests {
    private static let safely = "Dependi cannot edit this project file safely: "

    private func text(_ fixture: String) -> String {
        String(decoding: FixtureWorld.fixture(fixture), as: UTF8.self)
    }

    /// Runs the editor and expects one exact refusal, with nothing written and the file unchanged.
    private func expectRefusal(
        _ bytes: Data, reason: String, target: String = "MewTestsApp",
        bundle: String = "Settings.bundle",
        adjusting adjust: (@Sendable (BuildSetupPlan) -> BuildSetupPlan)? = nil,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let world = try EditWorld("x", bytes: bytes)
        let editor =
            adjust.map {
                ProjectFileEditor(files: world.files, writer: world.writer, adjustPlan: $0)
            } ?? world.editor
        #expect(
            throws: DomainError.fileUnreadable(path: EditWorld.projectFile, reason: reason),
            sourceLocation: sourceLocation
        ) {
            try editor.configureBuild(
                projectFilePath: EditWorld.projectFolder, targetName: target,
                settingsBundlePath: EditWorld.appFolder + "/" + bundle,
                backupPath: EditWorld.backup, isDryRun: false)
        }
        #expect(world.writer.records.isEmpty, sourceLocation: sourceLocation)
        #expect(try world.currentBytes() == bytes, sourceLocation: sourceLocation)
    }

    private func mini(settings: String?, resourceFiles: String = "") -> String {
        MiniProject.text(settings: settings, resourceFiles: resourceFiles)
    }

    // MARK: The planner

    @Test("a project with no section markers is refused when the phase needs a new section")
    func noSectionMarkers() throws {
        // Fila needs no file reference, so the first line to insert is the phase.
        let lines = text("synchronized-fila").split(
            separator: "\n", omittingEmptySubsequences: false
        ).filter { !$0.hasPrefix("/* Begin ") && !$0.hasPrefix("/* End ") }
        try expectRefusal(
            Data(lines.joined(separator: "\n").utf8),
            reason: Self.safely + "the section markers are missing", target: "Fila",
            bundle: "Fila/Settings.bundle")
    }

    @Test("a build setting that shares its line is refused")
    func settingNotOnItsOwnLine() throws {
        try expectRefusal(
            Data(mini(settings: "{ SDKROOT = iphoneos; }").utf8),
            reason: Self.safely + "a build setting is not on its own line", target: "App")
    }

    @Test(
        "a list whose last item shares its line or has its comma on another line is refused",
        arguments: ["\t\t\t\tX /* x */, Y,\n", "\t\t\t\tX\n\t\t\t\t,\n"])
    func listItemNotOnItsOwnLine(items: String) throws {
        try expectRefusal(
            Data(mini(settings: nil, resourceFiles: items).utf8),
            reason: Self.safely + "a list is not laid out in lines", target: "App")
    }

    @Test("an empty list whose closing bracket shares its line is refused")
    func emptyListOnOneLine() throws {
        let broken = replacing(
            mini(settings: nil), "files = (\n\t\t\t);", with: "files = ( );")
        try expectRefusal(
            Data(broken.utf8), reason: Self.safely + "a list is not laid out in lines",
            target: "App")
    }

    // MARK: The scanner

    @Test("a data literal is refused because the scanner does not allow its bytes")
    func byteNotAllowed() throws {
        // The parser reads `<0A>` as data, so the text reaches the scanner.
        let broken = replacing(
            text("old-format-mew"), "\tclasses = {\n\t};\n", with: "\tclasses = <0A>;\n")
        try expectRefusal(
            Data(broken.utf8), reason: Self.safely + "the text holds a byte that is not allowed")
    }

    /// Puts a first `objects` table before the real one. The parser keeps the last table and the
    /// scanner reads the first, so the scanner sees `OBJ_5`, the main group, as `group`.
    private func shadowed(group: String) -> Data {
        let shadow = "\tobjects = {\n\t\tOBJ_5 = \(group);\n\t};\n"
        return Data(
            replacing(text("old-format-mew"), "\tobjects = {\n", with: shadow + "\tobjects = {\n")
                .utf8)
    }

    @Test("an object that is not a dictionary in the text is refused")
    func dictionaryNotClosed() throws {
        try expectRefusal(
            shadowed(group: "none"), reason: Self.safely + "a dictionary is not closed")
    }

    @Test("a list written as a dictionary in the text is refused")
    func listNotClosed() throws {
        try expectRefusal(
            shadowed(group: "{ children = { }; }"), reason: Self.safely + "a list is not closed")
    }

    @Test("a list item without a comma in the text is refused")
    func listItemWithoutComma() throws {
        try expectRefusal(
            shadowed(group: "{ children = ( one ); }"),
            reason: Self.safely + "a list item does not end with a comma")
    }

    // MARK: The check of the edited project

    @Test("a plan that turns the build settings of an object into a list fails the check")
    func settingsNotADictionary() throws {
        let other =
            "\t\tH1 /* Release */ = {\n\t\t\tisa = XCBuildConfiguration;\n\t\t\tbuildSettings = {\n\t\t\t};\n\t\t\tname = Release;\n\t\t};\n"
        let source = replacing(
            mini(settings: "{\n\t\t\t}"), "/* End XCBuildConfiguration section */",
            with: other + "/* End XCBuildConfiguration section */")
        let marker = "buildSettings = {\n\t\t\t};\n\t\t\tname = Release;"
        let range = try #require(source.range(of: marker))
        let offset =
            source.utf8.distance(from: source.utf8.startIndex, to: range.lowerBound)
            + "buildSettings = ".utf8.count
        try expectRefusal(
            Data(source.utf8),
            reason:
                "the edit did not give the expected project (the build settings are not a dictionary). Nothing was written.",
            target: "App",
            adjusting: { plan in
                var plan = plan
                plan.edits.append(
                    PBXTextEdit(
                        offset: offset, removeCount: "{\n\t\t\t}".utf8.count,
                        insertText: "(\n\t\t\t)"))
                plan.editedIDs.insert("H1")
                return plan
            })
    }

    @Test("a plan that renames the target fails the check even though the target is edited")
    func renameIsRefused() throws {
        let source = text("old-format-mew")
        let marker = "\t\t\tname = MewTestsApp;\n\t\t\tproductName = MewTestsApp;\n"
        let range = try #require(source.range(of: marker))
        let offset = source.utf8.distance(from: source.utf8.startIndex, to: range.lowerBound)
        try expectRefusal(
            Data(source.utf8),
            reason:
                "the edit did not give the expected project (the key name changed). Nothing was written.",
            adjusting: { plan in
                var plan = plan
                plan.edits.append(
                    PBXTextEdit(
                        offset: offset, removeCount: "\t\t\tname = MewTestsApp;\n".utf8.count,
                        insertText: "\t\t\tname = Renamed;\n"))
                return plan
            })
    }

    @Test(
        "a plan that gives an edited object a new path or source tree fails the check",
        arguments: ["path", "sourceTree"])
    func pathAndSourceTreeAreRefused(key: String) throws {
        let source = text("old-format-mew")
        let marker = "\t\t\tproductName = MewTestsApp;\n"
        let range = try #require(source.range(of: marker))
        let offset = source.utf8.distance(from: source.utf8.startIndex, to: range.lowerBound)
        try expectRefusal(
            Data(source.utf8),
            reason:
                "the edit did not give the expected project (the key \(key) changed). Nothing was written.",
            adjusting: { plan in
                var plan = plan
                plan.edits.append(
                    PBXTextEdit(offset: offset, removeCount: 0, insertText: "\t\t\t\(key) = x;\n"))
                return plan
            })
    }

    // MARK: The layout of the file

    @Test("a file whose first byte is a space is refused")
    func leadingSpace() throws {
        try expectRefusal(
            Data((" " + text("old-format-mew")).utf8),
            reason: Self.safely + "the lines are indented with spaces")
    }
}
