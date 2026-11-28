import Foundation
import Testing

@Suite("Project file editor re-run", .timeLimit(.minutes(1)))
struct BuildEditRerunTests {
    @Test(
        "a second run is byte identical, reports nothing and writes nothing",
        arguments: EditCase.all)
    func rerunIsIdentical(_ item: EditCase) throws {
        let world = try EditWorld(item.fixture)
        try world.configure(target: item.target, bundle: item.bundle)
        let afterFirst = try world.currentBytes()
        let writes = world.writer.records
        let lines = try world.configure(target: item.target, bundle: item.bundle)
        #expect(lines == [], "\(item.fixture)")
        #expect(try world.currentBytes() == afterFirst)
        #expect(world.writer.records == writes)
        // The backup still holds the original, not the edited bytes.
        let backup = try world.files.readRegularFile(at: EditWorld.backup, upToBytes: Int.max)
        #expect(backup == world.original)
    }

    @Test("a project that is already set up gets no backup at all")
    func alreadySetUpWritesNoBackup() throws {
        let first = try EditWorld("synchronized-fila")
        try first.configure(target: "Fila", bundle: "Fila/Settings.bundle")
        let second = try EditWorld("x", bytes: try first.currentBytes())
        #expect(try second.configure(target: "Fila", bundle: "Fila/Settings.bundle") == [])
        #expect(second.writer.records.isEmpty)
        #expect(!second.files.exists(at: EditWorld.backup))
    }
}
