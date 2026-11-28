import DependiDomain
import Foundation
import Testing

@testable import DependiProjectFile

/// The first backup is kept for ever. Later backups go beside it with a number.
@Suite("Project file editor backups", .timeLimit(.minutes(1)))
struct BuildEditBackupTests {
    private static let first = EditWorld.backup
    private static let second = EditWorld.backup + ".2"
    private static let third = EditWorld.backup + ".3"

    private func bytes(_ world: EditWorld, _ path: String) throws -> Data {
        try world.files.readRegularFile(at: path, upToBytes: Int.max)
    }

    @Test("a second edit keeps the first backup and writes the next one beside it")
    func secondEditKeepsFirstBackup() throws {
        let world = try EditWorld("synchronized-fila")
        let firstRun = try world.configure(target: "Fila", bundle: "Fila/Settings.bundle")
        #expect(
            firstRun == [
                "Dependi: added the Dependi Run Script phase after Copy Bundle Resources of Fila.",
                "Dependi: set ENABLE_USER_SCRIPT_SANDBOXING = NO in Debug of Fila.",
                "Dependi: set ENABLE_USER_SCRIPT_SANDBOXING = NO in Release of Fila.",
                "Dependi: backup of the original project file is at /work/App/.dependi/project.pbxproj.bak.",
            ])
        let afterFirst = try world.currentBytes()
        let secondRun = try world.configure(
            target: "FilaSandboxed", bundle: "Fila/Settings.bundle")
        #expect(
            secondRun == [
                "Dependi: added the Dependi Run Script phase after Copy Bundle Resources of FilaSandboxed.",
                "Dependi: set ENABLE_USER_SCRIPT_SANDBOXING = NO in Debug of FilaSandboxed.",
                "Dependi: set ENABLE_USER_SCRIPT_SANDBOXING = NO in Release of FilaSandboxed.",
                "Dependi: backup of the project file before this edit is at /work/App/.dependi/project.pbxproj.bak.2.",
            ])
        #expect(try bytes(world, Self.first) == world.original)
        #expect(try bytes(world, Self.second) == afterFirst)
        #expect(try world.currentBytes() != afterFirst)
        #expect(
            world.writer.records == [
                "mkdir /work/App/.dependi",
                "write /work/App/.dependi/project.pbxproj.bak",
                "write /work/App/App.xcodeproj/project.pbxproj.dependi-new",
                "move /work/App/App.xcodeproj/project.pbxproj.dependi-new to /work/App/App.xcodeproj/project.pbxproj",
                "mkdir /work/App/.dependi",
                "write /work/App/.dependi/project.pbxproj.bak.2",
                "write /work/App/App.xcodeproj/project.pbxproj.dependi-new",
                "move /work/App/App.xcodeproj/project.pbxproj.dependi-new to /work/App/App.xcodeproj/project.pbxproj",
            ])
    }

    @Test("a third edit goes to .3 when .bak and .bak.2 exist and leaves both alone")
    func thirdEditGoesToNumberThree() throws {
        let world = try EditWorld("old-format-mew")
        try world.files.addFile(at: Self.first, contents: Data("first".utf8))
        try world.files.addFile(at: Self.second, contents: Data("second".utf8))
        let lines = try world.configure(target: "MewTestsApp", bundle: "Settings.bundle")
        #expect(
            lines.last
                == "Dependi: backup of the project file before this edit is at /work/App/.dependi/project.pbxproj.bak.3."
        )
        #expect(try bytes(world, Self.first) == Data("first".utf8))
        #expect(try bytes(world, Self.second) == Data("second".utf8))
        #expect(try bytes(world, Self.third) == world.original)
    }

    @Test("the next free number is the lowest one that is free, even after a gap")
    func lowestFreeNumber() throws {
        let world = try EditWorld("old-format-mew")
        try world.files.addFile(at: Self.first, contents: Data("first".utf8))
        try world.files.addFile(at: Self.third, contents: Data("third".utf8))
        let lines = try world.configure(target: "MewTestsApp", bundle: "Settings.bundle")
        #expect(
            lines.last
                == "Dependi: backup of the project file before this edit is at /work/App/.dependi/project.pbxproj.bak.2."
        )
        #expect(try bytes(world, Self.second) == world.original)
        #expect(try bytes(world, Self.third) == Data("third".utf8))
    }

    @Test("a run that changes nothing writes no backup and prints no backup line")
    func rerunWritesNoBackup() throws {
        let world = try EditWorld("synchronized-fila")
        try world.configure(target: "Fila", bundle: "Fila/Settings.bundle")
        let writes = world.writer.records
        let lines = try world.configure(target: "Fila", bundle: "Fila/Settings.bundle")
        #expect(lines == [])
        #expect(world.writer.records == writes)
        #expect(!world.files.exists(at: Self.second))
    }

    @Test("a dry run names the numbered path that a real run would write and writes nothing")
    func dryRunNamesNumberedPath() throws {
        let world = try EditWorld("old-format-mew")
        try world.files.addFile(at: Self.first, contents: Data("first".utf8))
        let lines = try world.configure(
            target: "MewTestsApp", bundle: "Settings.bundle", isDryRun: true)
        #expect(
            lines.last
                == "Dependi: backup of the project file before this edit is at /work/App/.dependi/project.pbxproj.bak.2."
        )
        #expect(world.writer.records.isEmpty)
        #expect(!world.files.exists(at: Self.second))
        #expect(try world.currentBytes() == world.original)
    }

    @Test(
        "when every backup number is taken the edit is refused, names the folder and writes nothing"
    )
    func everyNumberTaken() throws {
        let world = try EditWorld("old-format-mew")
        for path in [Self.first, Self.second, Self.third] {
            try world.files.addFile(at: path, contents: Data("old".utf8))
        }
        let editor = ProjectFileEditor(
            files: world.files, writer: world.writer, adjustPlan: { $0 }, lastBackupNumber: 3)
        #expect(
            throws: DomainError.fileUnwritable(
                path: "/work/App/.dependi",
                reason:
                    "every backup name from .2 to .3 is taken in this folder. Remove old backups, then run again"
            )
        ) {
            try editor.configureBuild(
                projectFilePath: EditWorld.projectFolder, targetName: "MewTestsApp",
                settingsBundlePath: "/work/App/Settings.bundle", backupPath: Self.first,
                isDryRun: false)
        }
        #expect(world.writer.records.isEmpty)
        #expect(try world.currentBytes() == world.original)
    }
}
