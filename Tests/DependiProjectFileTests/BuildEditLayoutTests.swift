import DependiDomain
import DependiProjectFile
import Foundation
import Testing

@Suite("Project file editor layouts", .timeLimit(.minutes(1)))
struct BuildEditLayoutTests {
    private func world(settings: String?) throws -> EditWorld {
        let text = MiniProject.text(settings: settings, resourceFiles: "")
        return try EditWorld("x", bytes: Data(text.utf8))
    }

    @Test("a project with no later section gets the new section at the end")
    func sectionAtTheEnd() throws {
        let world = try world(settings: nil)
        let lines = try world.configure(target: "App", bundle: "Settings.bundle")
        #expect(lines.count == 4)
        let text = try world.currentText()
        #expect(
            text.contains(
                "/* End PBXResourcesBuildPhase section */\n\n/* Begin PBXShellScriptBuildPhase section */\n"
            ))
        #expect(
            text.hasSuffix(
                "/* End PBXShellScriptBuildPhase section */\n\t};\n\trootObject = F0 /* Project object */;\n}\n"
            ))
    }

    @Test("an empty list gets its first item one tab deeper than the closing bracket")
    func emptyList() throws {
        let world = try world(settings: nil)
        try world.configure(target: "App", bundle: "Settings.bundle")
        let text = try world.currentText()
        let pattern = try Regex(
            #"files = \(\n\t\t\t\t[0-9A-F]{24} /\* Settings\.bundle in Resources \*/,\n\t\t\t\);"#)
        #expect(text.firstMatch(of: pattern) != nil)
    }

    @Test("an empty build settings dictionary on several lines gets the setting")
    func emptySettings() throws {
        let world = try world(settings: "{\n\t\t\t}")
        let lines = try world.configure(target: "App", bundle: "Settings.bundle")
        #expect(lines.contains("Dependi: set ENABLE_USER_SCRIPT_SANDBOXING = NO in Debug of App."))
        #expect(
            try world.currentText().contains(
                "buildSettings = {\n\t\t\t\tENABLE_USER_SCRIPT_SANDBOXING = NO;\n\t\t\t};"))
    }

    @Test("build settings on one line are refused and nothing is written")
    func oneLineSettings() throws {
        let world = try world(settings: "{}")
        do {
            try world.configure(target: "App", bundle: "Settings.bundle")
            Issue.record("expected a refusal")
        } catch {
            #expect("\(error)".contains("laid out in lines"), "\(error)")
        }
        #expect(world.writer.records.isEmpty)
    }

    @Test("a backup that does not match the original is removed and the project is not replaced")
    func backupMismatch() throws {
        let world = try EditWorld("old-format-mew", alteringPrefix: "write \(EditWorld.backup)")
        #expect(
            throws: DomainError.fileUnwritable(
                path: EditWorld.backup,
                reason:
                    "the backup did not match the original, so it was removed. The project file was not changed."
            )
        ) { try world.configure(target: "MewTestsApp", bundle: "Settings.bundle") }
        #expect(
            world.writer.records == [
                "mkdir \(EditWorld.appFolder)/.dependi", "write \(EditWorld.backup)",
                "remove \(EditWorld.backup)",
            ])
        #expect(!world.files.exists(at: EditWorld.backup))
        #expect(try world.currentBytes() == world.original)
        // A second run with a normal writer starts again with a fresh backup.
        let editor = ProjectFileEditor(files: world.files, writer: RecordingWriter(world.files))
        let lines = try editor.configureBuild(
            projectFilePath: EditWorld.projectFolder, targetName: "MewTestsApp",
            settingsBundlePath: EditWorld.appFolder + "/Settings.bundle",
            backupPath: EditWorld.backup, isDryRun: false)
        #expect(
            lines.last
                == "Dependi: backup of the original project file is at /work/App/.dependi/project.pbxproj.bak."
        )
        #expect(!lines.contains { $0.contains("kept") })
        #expect(
            try world.files.readRegularFile(at: EditWorld.backup, upToBytes: Int.max)
                == world.original)
        #expect(try world.currentBytes() != world.original)
    }

    @Test("a backup that cannot be read back is removed and the project is not replaced")
    func backupReadbackFailsIsRemoved() throws {
        let world = try EditWorld(
            "old-format-mew", unreadablePrefix: "write \(EditWorld.backup)")
        #expect(
            throws: DomainError.fileUnwritable(
                path: EditWorld.backup,
                reason:
                    "the backup did not match the original, so it was removed. The project file was not changed."
            )
        ) { try world.configure(target: "MewTestsApp", bundle: "Settings.bundle") }
        #expect(
            world.writer.records == [
                "mkdir \(EditWorld.appFolder)/.dependi", "write \(EditWorld.backup)",
                "remove \(EditWorld.backup)",
            ])
        #expect(!world.files.exists(at: EditWorld.backup))
        #expect(try world.currentBytes() == world.original)
    }

    @Test("a bad backup that cannot be removed is reported as left in place")
    func backupMismatchRemovalFails() throws {
        let world = try EditWorld(
            "old-format-mew", failingPrefix: "remove ", alteringPrefix: "write \(EditWorld.backup)")
        #expect(
            throws: DomainError.fileUnwritable(
                path: EditWorld.backup,
                reason:
                    "the backup did not match the original and it could not be removed. Remove it by hand. The project file was not changed."
            )
        ) { try world.configure(target: "MewTestsApp", bundle: "Settings.bundle") }
        #expect(!world.writer.records.contains { $0.contains("dependi-new") })
        #expect(try world.currentBytes() == world.original)
    }

    private func expectBackupRefused(_ world: EditWorld, isDryRun: Bool = false) throws {
        #expect(
            throws: DomainError.fileUnwritable(
                path: EditWorld.backup,
                reason:
                    "something other than a regular file is at the backup path. Move it away, then run again. Nothing was written."
            )
        ) {
            try world.configure(
                target: "MewTestsApp", bundle: "Settings.bundle", isDryRun: isDryRun)
        }
        #expect(world.writer.records.isEmpty)
        #expect(try world.currentBytes() == world.original)
    }

    @Test("a folder at the backup path is refused and nothing is written")
    func folderAtBackupPath() throws {
        let world = try EditWorld("old-format-mew")
        try world.files.addDirectory(at: EditWorld.backup)
        try expectBackupRefused(world)
        try expectBackupRefused(world, isDryRun: true)
    }

    @Test("a link at the backup path is refused even when it points at a regular file")
    func linkAtBackupPath() throws {
        let world = try EditWorld("old-format-mew")
        try world.files.addFile(at: "/work/App/elsewhere.bak", contents: world.original)
        try world.files.addSymlink(at: EditWorld.backup, pointingTo: "/work/App/elsewhere.bak")
        try expectBackupRefused(world)
    }

    @Test("a link to nothing at the backup path is refused")
    func danglingLinkAtBackupPath() throws {
        let world = try EditWorld("old-format-mew")
        try world.files.addSymlink(at: EditWorld.backup, pointingTo: "/work/App/missing.bak")
        try expectBackupRefused(world)
    }

    @Test("the path of the project file itself works as well as the path of its folder")
    func projectFilePathIsAccepted() throws {
        let world = try EditWorld("old-format-mew")
        let lines = try world.editor.configureBuild(
            projectFilePath: EditWorld.projectFile, targetName: "MewTestsApp",
            settingsBundlePath: "/work/App/Settings.bundle", backupPath: EditWorld.backup,
            isDryRun: false)
        #expect(lines.count == 6)
    }
}
