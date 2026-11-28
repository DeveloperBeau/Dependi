import DependiDomain
import Foundation
import Testing

@testable import DependiProjectFile

@Suite("Project file editor refusals", .timeLimit(.minutes(1)))
struct BuildEditRefusalTests {
    private func text(_ fixture: String) -> String {
        String(decoding: FixtureWorld.fixture(fixture), as: UTF8.self)
    }

    /// Runs the editor on bytes and expects a refusal that writes nothing.
    private func expectRefusal(
        _ bytes: Data, target: String = "MewTestsApp", bundle: String = "Settings.bundle",
        contains words: String? = nil, sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let world = try EditWorld("x", bytes: bytes)
        do {
            try world.configure(target: target, bundle: bundle)
            Issue.record("expected a refusal", sourceLocation: sourceLocation)
        } catch {
            if let words {
                #expect("\(error)".contains(words), "\(error)", sourceLocation: sourceLocation)
            }
        }
        #expect(world.writer.records.isEmpty, sourceLocation: sourceLocation)
        #expect(try world.currentBytes() == bytes, sourceLocation: sourceLocation)
    }

    @Test("text that is not a project file is refused and nothing is written")
    func unparseableFile() throws {
        try expectRefusal(Data("not a project".utf8))
    }

    @Test("a file cut in the middle is refused at every cut")
    func cutFile() throws {
        let bytes = FixtureWorld.fixture("old-format-mew")
        for fraction in [10, 30, 50, 70, 90, 99] {
            try expectRefusal(bytes.prefix(bytes.count * fraction / 100))
        }
    }

    @Test("a comment that is not closed is refused")
    func unclosedComment() throws {
        try expectRefusal(Data((text("old-format-mew") + "/* open").utf8))
    }

    @Test("a bad header line is refused")
    func badHeader() throws {
        try expectRefusal(
            Data(replacing(text("old-format-mew"), "// !$*UTF8*$!", with: "<?xml?>").utf8))
    }

    @Test("a root that is a list is refused")
    func badRoot() throws {
        try expectRefusal(Data("// !$*UTF8*$!\n( a, b )\n".utf8))
    }

    @Test("bytes that are not UTF-8 are refused")
    func notUTF8() throws {
        var bytes = FixtureWorld.fixture("old-format-mew")
        bytes.append(contentsOf: [0xFF, 0xFE])
        try expectRefusal(bytes)
        var inside = Data(text("old-format-mew").utf8)
        let marker = Data("/* Begin PBXBuildFile section */".utf8)
        let range = try #require(inside.range(of: marker))
        inside.replaceSubrange(range.upperBound..<range.upperBound, with: [0xFF])
        try expectRefusal(inside)
    }

    @Test("lines that end with CR LF are refused")
    func crlf() throws {
        let crlf = text("old-format-mew").replacingOccurrences(of: "\n", with: "\r\n")
        try expectRefusal(Data(crlf.utf8), contains: "CR LF")
    }

    @Test("a file indented with spaces is refused")
    func spaceIndented() throws {
        let spaces = text("old-format-mew").replacingOccurrences(of: "\t", with: "    ")
        try expectRefusal(Data(spaces.utf8), contains: "spaces")
    }

    @Test("missing section markers are refused when a line must go in that section")
    func missingSectionMarkers() throws {
        let broken = replacing(
            text("old-format-mew"), "/* Begin PBXBuildFile section */", with: "")
        try expectRefusal(Data(broken.utf8), contains: "PBXBuildFile")
    }

    @Test("a target with no Copy Bundle Resources phase is refused")
    func noResourcesPhase() throws {
        let broken = replacing(
            text("old-format-mew"), "\t\t\t\tD2568DEA214BCA3B00FCA44A /* Resources */,\n", with: "")
        try expectRefusal(Data(broken.utf8), contains: "Copy Bundle Resources")
    }

    @Test("a different Settings.bundle in the target is refused")
    func differentBundle() throws {
        try expectRefusal(
            FixtureWorld.fixture("folder-reference-twittertexteditor"), target: "Example",
            bundle: "Example/Settings.bundle", contains: "another Settings.bundle")
    }

    @Test("a bundle outside the project folder or with another name is refused")
    func bundleOutsideFolder() throws {
        let bytes = FixtureWorld.fixture("old-format-mew")
        for path in [
            "/elsewhere/Settings.bundle", "/work/App/Other.bundle", "/work/App/../Settings.bundle",
        ] {
            let world = try EditWorld("x", bytes: bytes)
            do {
                try world.editor.configureBuild(
                    projectFilePath: EditWorld.projectFolder, targetName: "MewTestsApp",
                    settingsBundlePath: path, backupPath: EditWorld.backup, isDryRun: false)
                Issue.record("expected a refusal for \(path)")
            } catch {
                #expect("\(error)".contains("not inside the project folder"), "\(path): \(error)")
            }
            #expect(world.writer.records.isEmpty)
        }
    }

    @Test("an unknown target is refused and the message names the targets")
    func unknownTarget() throws {
        try expectRefusal(
            FixtureWorld.fixture("old-format-mew"), target: "Nope",
            contains: "Available targets: Mew, MewTests, MewTestsApp")
    }

    @Test("a folder that leaves the bundle out of the target is refused")
    func synchronizedExceptionRefuses() throws {
        let bytes = Data(try Self.filaWithException(target: "FA0000000000000000000043").utf8)
        try expectRefusal(
            bytes, target: "Fila", bundle: "Fila/Settings.bundle",
            contains: "leaves Settings.bundle out")
    }

    @Test("an exception that belongs to another target does not stop the edit")
    func exceptionOfAnotherTarget() throws {
        let text = try Self.filaWithException(target: "FA1000000000000000000010")
        let world = try EditWorld("x", bytes: Data(text.utf8))
        let lines = try world.configure(target: "Fila", bundle: "Fila/Settings.bundle")
        #expect(lines.contains { $0.contains("Run Script phase") })
    }

    private static func filaWithException(target: String) throws -> String {
        var text = String(decoding: FixtureWorld.fixture("synchronized-fila"), as: UTF8.self)
        text = replacing(
            text, "\t\t\tisa = PBXFileSystemSynchronizedRootGroup;\n\t\t\tpath = Fila;\n",
            with:
                "\t\t\tisa = PBXFileSystemSynchronizedRootGroup;\n\t\t\texceptions = (\n\t\t\t\tFA9900000000000000000001 /* Exceptions */,\n\t\t\t);\n\t\t\tpath = Fila;\n"
        )
        let set =
            "\t\tFA9900000000000000000001 /* Exceptions */ = {\n\t\t\tisa = PBXFileSystemSynchronizedBuildFileExceptionSet;\n\t\t\tmembershipExceptions = (\n\t\t\t\tSettings.bundle,\n\t\t\t);\n\t\t\ttarget = \(target);\n\t\t};\n"
        return replacing(
            text, "/* End PBXFileSystemSynchronizedRootGroup section */",
            with: set + "/* End PBXFileSystemSynchronizedRootGroup section */")
    }

    @Test(
        "the backup is written before the project file and the project file is replaced by a move")
    func backupFirst() throws {
        let world = try EditWorld("old-format-mew")
        try world.configure(target: "MewTestsApp", bundle: "Settings.bundle")
        #expect(world.writer.records.dropFirst().first == "write \(EditWorld.backup)")
        #expect(world.writer.records.count == 4)
        let backup = try world.files.readRegularFile(at: EditWorld.backup, upToBytes: Int.max)
        #expect(backup == world.original)
    }

    @Test("a backup that cannot be written leaves the project file untouched")
    func backupWriteFails() throws {
        let world = try EditWorld("old-format-mew", failingPrefix: "write \(EditWorld.backup)")
        #expect(throws: DomainError.self) {
            try world.configure(target: "MewTestsApp", bundle: "Settings.bundle")
        }
        #expect(
            world.writer.records == [
                "mkdir \(EditWorld.appFolder)/.dependi", "write \(EditWorld.backup)",
            ])
        #expect(try world.currentBytes() == world.original)
    }

    @Test("a project write that fails keeps the backup and the original")
    func projectWriteFails() throws {
        let world = try EditWorld(
            "old-format-mew", failingPrefix: "write \(EditWorld.projectFile).dependi-new")
        #expect(throws: DomainError.self) {
            try world.configure(target: "MewTestsApp", bundle: "Settings.bundle")
        }
        #expect(try world.currentBytes() == world.original)
        let backup = try world.files.readRegularFile(at: EditWorld.backup, upToBytes: Int.max)
        #expect(backup == world.original)
        #expect(world.writer.records.contains("remove \(EditWorld.projectFile).dependi-new"))
    }

    // MARK: A plan that does not give the expected project

    private func world(adjusting adjust: @escaping @Sendable (BuildSetupPlan) -> BuildSetupPlan)
        throws
        -> (EditWorld, ProjectFileEditor)
    {
        let world = try EditWorld("old-format-mew")
        return (
            world, ProjectFileEditor(files: world.files, writer: world.writer, adjustPlan: adjust)
        )
    }

    private func run(_ editor: ProjectFileEditor) throws(DomainError) -> [String] {
        try editor.configureBuild(
            projectFilePath: EditWorld.projectFolder, targetName: "MewTestsApp",
            settingsBundlePath: "/work/App/Settings.bundle", backupPath: EditWorld.backup,
            isDryRun: false)
    }

    @Test("a plan that lists an object that is not there fails the check and writes nothing")
    func verifierObjectCount() throws {
        let (world, editor) = try world { plan in
            var plan = plan
            plan.addedIDs.insert("FFFFFFFFFFFFFFFFFFFFFFFF")
            return plan
        }
        #expect(throws: DomainError.self) { try run(editor) }
        #expect(world.writer.records.isEmpty)
    }

    @Test("a plan that changes an object it did not list fails the check and writes nothing")
    func verifierUnplannedChange() throws {
        let (world, editor) = try world { plan in
            var plan = plan
            plan.editedIDs = []
            return plan
        }
        #expect(throws: DomainError.self) { try run(editor) }
        #expect(world.writer.records.isEmpty)
    }

    @Test("a plan that leaves a step open fails the check and writes nothing")
    func verifierStepStillOpen() throws {
        let (world, editor) = try world { plan in
            var plan = plan
            plan.edits.removeAll { $0.insertText.contains("ENABLE_USER_SCRIPT_SANDBOXING") }
            return plan
        }
        #expect(throws: DomainError.self) { try run(editor) }
        #expect(world.writer.records.isEmpty)
    }

    @Test("a plan that changes another build setting fails the check and writes nothing")
    func verifierOtherSetting() throws {
        let (world, editor) = try world { plan in
            var plan = plan
            plan.edits = plan.edits.map {
                $0.insertText.contains("ENABLE_USER_SCRIPT_SANDBOXING")
                    ? PBXTextEdit(
                        offset: $0.offset, removeCount: 0,
                        insertText: $0.insertText + "\t\t\t\tOTHER_SETTING = 1;\n")
                    : $0
            }
            return plan
        }
        #expect(throws: DomainError.self) { try run(editor) }
        #expect(world.writer.records.isEmpty)
    }

    @Test("a plan that changes a key that may not change fails the check and writes nothing")
    func verifierOtherKey() throws {
        let source = String(decoding: FixtureWorld.fixture("old-format-mew"), as: UTF8.self)
        let marker = "\t\t\tproductName = MewTestsApp;\n"
        let range = try #require(source.range(of: marker))
        let offset = source.utf8.distance(from: source.utf8.startIndex, to: range.lowerBound)
        let (world, editor) = try world { plan in
            var plan = plan
            plan.edits.append(
                PBXTextEdit(offset: offset, removeCount: 0, insertText: "\t\t\tcomments = x;\n"))
            return plan
        }
        do {
            _ = try run(editor)
            Issue.record("expected a refusal")
        } catch {
            #expect("\(error)".contains("the key comments changed"), "\(error)")
        }
        #expect(world.writer.records.isEmpty)
    }

    @Test("a plan that removes a list entry fails the check and writes nothing")
    func verifierListLosesEntry() throws {
        let source = String(decoding: FixtureWorld.fixture("old-format-mew"), as: UTF8.self)
        let marker = "\t\t\t\tD2568DE9214BCA3B00FCA44A /* Frameworks */,\n"
        let range = try #require(source.range(of: marker))
        let offset = source.utf8.distance(from: source.utf8.startIndex, to: range.lowerBound)
        let (world, editor) = try world { plan in
            var plan = plan
            plan.edits.append(
                PBXTextEdit(offset: offset, removeCount: marker.utf8.count, insertText: ""))
            return plan
        }
        #expect(throws: DomainError.self) { try run(editor) }
        #expect(world.writer.records.isEmpty)
    }
}
