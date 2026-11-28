import DependiDomain
import Foundation
import Testing

@testable import DependiProjectFile

/// The backup is written only when none exists, so it is always the original.
@Suite("Project file editor backups", .timeLimit(.minutes(1)))
struct BuildEditBackupTests {
    private static let kept =
        "Dependi: kept the backup of the original project file at /work/App/.dependi/project.pbxproj.bak."

    private func bytes(_ world: EditWorld, _ path: String) throws -> Data {
        try world.files.readRegularFile(at: path, upToBytes: Int.max)
    }

    @Test("a second edit leaves the first backup as the original and writes no other backup")
    func secondEditKeepsOriginalBackup() throws {
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
                Self.kept,
            ])
        #expect(try bytes(world, EditWorld.backup) == world.original)
        #expect(!world.files.exists(at: EditWorld.backup + ".2"))
        #expect(try world.currentBytes() != afterFirst)
        #expect(
            world.writer.records == [
                "mkdir /work/App/.dependi",
                "write /work/App/.dependi/project.pbxproj.bak",
                "write /work/App/App.xcodeproj/project.pbxproj.dependi-new",
                "move /work/App/App.xcodeproj/project.pbxproj.dependi-new to /work/App/App.xcodeproj/project.pbxproj",
                "write /work/App/App.xcodeproj/project.pbxproj.dependi-new",
                "move /work/App/App.xcodeproj/project.pbxproj.dependi-new to /work/App/App.xcodeproj/project.pbxproj",
            ])
    }

    @Test("a backup that already exists is left byte for byte alone and the kept line is printed")
    func existingBackupIsKept() throws {
        let world = try EditWorld("old-format-mew")
        try world.files.addFile(at: EditWorld.backup, contents: Data("older".utf8))
        let lines = try world.configure(target: "MewTestsApp", bundle: "Settings.bundle")
        #expect(lines.last == Self.kept)
        #expect(try bytes(world, EditWorld.backup) == Data("older".utf8))
        #expect(!world.writer.records.contains("write \(EditWorld.backup)"))
        #expect(!world.files.exists(at: EditWorld.backup + ".2"))
        #expect(try world.currentBytes() != world.original)
    }

    @Test("a run that changes nothing writes no backup and prints no backup line")
    func rerunWritesNoBackup() throws {
        let world = try EditWorld("synchronized-fila")
        try world.configure(target: "Fila", bundle: "Fila/Settings.bundle")
        let writes = world.writer.records
        let lines = try world.configure(target: "Fila", bundle: "Fila/Settings.bundle")
        #expect(lines == [])
        #expect(world.writer.records == writes)
        #expect(!world.files.exists(at: EditWorld.backup + ".2"))
    }

    @Test("a dry run when the backup exists prints the kept line and writes nothing")
    func dryRunKeptLine() throws {
        let world = try EditWorld("old-format-mew")
        try world.files.addFile(at: EditWorld.backup, contents: Data("older".utf8))
        let lines = try world.configure(
            target: "MewTestsApp", bundle: "Settings.bundle", isDryRun: true)
        #expect(lines.last == Self.kept)
        #expect(world.writer.records.isEmpty)
        #expect(try bytes(world, EditWorld.backup) == Data("older".utf8))
        #expect(try world.currentBytes() == world.original)
    }
}
