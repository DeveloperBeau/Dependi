import DependiDomain
import DependiProjectFile
import Foundation
import TestHelpers
import Testing

@Suite("Project file editor fuzz", .timeLimit(.minutes(3)))
struct BuildEditFuzzTests {
    private static let seed: UInt64 = 0x00D3_9E4D_1C0F_FEE5

    private func text(_ fixture: String) -> String {
        String(decoding: FixtureWorld.fixture(fixture), as: UTF8.self)
    }

    @Test("damaged bytes either refuse and write nothing, or give a file that still loads")
    func randomByteDamage() throws {
        var generator = SeededGenerator(seed: Self.seed)
        print("fuzz seed for randomByteDamage: \(generator.seed)")
        let original = FixtureWorld.fixture("old-format-mew")
        var refused = 0
        var edited = 0
        for round in 0..<300 {
            var bytes = original
            for _ in 0..<Int.random(in: 1...4, using: &generator) {
                let index = Int.random(in: 0..<bytes.count, using: &generator)
                bytes[index] = UInt8.random(in: 0...255, using: &generator)
            }
            let world = try EditWorld("x", bytes: bytes)
            do {
                let lines = try world.configure(target: "MewTestsApp", bundle: "Settings.bundle")
                edited += 1
                let reader = ProjectFileReader(files: world.files)
                // A project that was edited must still be one that the reader opens.
                _ = try reader.applicationTargets(projectFilePath: EditWorld.projectFolder)
                #expect(
                    !lines.isEmpty || world.writer.records.isEmpty,
                    "seed \(Self.seed) round \(round)")
            } catch {
                refused += 1
                #expect(world.writer.records.isEmpty, "seed \(Self.seed) round \(round): \(error)")
                #expect(try world.currentBytes() == bytes, "seed \(Self.seed) round \(round)")
            }
        }
        #expect(
            refused > 0 && edited > 0, "seed \(Self.seed): refused \(refused), edited \(edited)")
    }

    @Test("a phase name or setting in a comment or a string is not taken for the real one")
    func falsePositive() throws {
        var generator = SeededGenerator(seed: Self.seed &+ 1)
        print("fuzz seed for falsePositive: \(generator.seed)")
        let source = text("old-format-mew")
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        // Comment lines go between two lines inside the objects table, where a comment is legal.
        let first = try #require(lines.firstIndex { $0.hasPrefix("/* Begin PBXBuildFile") })
        let planted = [
            "\t\t/* \"${SRCROOT}/.dependi/run.sh\" generate */",
            "\t\t// ENABLE_USER_SCRIPT_SANDBOXING = NO;",
            "\t\t/* isa = PBXShellScriptBuildPhase; shellScript = \".dependi/run.sh\"; */",
        ]
        for round in 0..<100 {
            var damaged = lines
            for _ in 0..<Int.random(in: 1...6, using: &generator) {
                let at = Int.random(in: (first + 1)..<(damaged.count - 5), using: &generator)
                // Only a spot between two single line entries or two dictionary lines is chosen.
                if damaged[at].hasPrefix("\t") {
                    damaged.insert(planted.randomElement(using: &generator)!, at: at)
                }
            }
            let world = try EditWorld("x", bytes: Data(damaged.joined(separator: "\n").utf8))
            let result = try world.configure(target: "MewTestsApp", bundle: "Settings.bundle")
            #expect(
                result.contains { $0.contains("Run Script phase") },
                "seed \(Self.seed &+ 1) round \(round)")
            #expect(
                result.filter { $0.contains("ENABLE_USER_SCRIPT_SANDBOXING = NO") }.count == 2,
                "seed \(Self.seed &+ 1) round \(round)")
        }
    }

    @Test("a project that is set up in another spelling is found done")
    func falseNegative() throws {
        var generator = SeededGenerator(seed: Self.seed &+ 2)
        print("fuzz seed for falseNegative: \(generator.seed)")
        let done = try EditWorld("old-format-mew")
        try done.configure(target: "MewTestsApp", bundle: "Settings.bundle")
        let source = try done.currentText()
        let spellings = [
            "ENABLE_USER_SCRIPT_SANDBOXING = NO;",
            "ENABLE_USER_SCRIPT_SANDBOXING = \"NO\";",
            "\"ENABLE_USER_SCRIPT_SANDBOXING\" = NO;",
            "ENABLE_USER_SCRIPT_SANDBOXING   =   NO  ;",
            "ENABLE_USER_SCRIPT_SANDBOXING /* why */ = /* x */ \"NO\";",
        ]
        for round in 0..<100 {
            var text = source
            let line = "\t\t\t\tENABLE_USER_SCRIPT_SANDBOXING = NO;\n"
            var rebuilt = ""
            var rest = text[...]
            while let range = rest.range(of: line) {
                rebuilt += rest[..<range.lowerBound]
                rebuilt += "\t\t\t\t" + spellings.randomElement(using: &generator)! + "\n"
                rest = rest[range.upperBound...]
            }
            text = rebuilt + rest
            let world = try EditWorld("x", bytes: Data(text.utf8))
            let result = try world.configure(target: "MewTestsApp", bundle: "Settings.bundle")
            #expect(result == [], "seed \(Self.seed &+ 2) round \(round)")
            #expect(world.writer.records.isEmpty)
        }
    }
}
