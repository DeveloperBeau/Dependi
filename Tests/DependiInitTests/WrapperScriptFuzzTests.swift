import Foundation
import TestHelpers
import Testing

@Suite("Wrapper script fuzz")
struct WrapperScriptFuzzTests {
    private static let versionAlphabet = Array("0123456789..  ;$`\n/-ab\"'\\")
    private static let commitAlphabet = Array("0123456789abcdefABCDEFg ;$`\n/.")

    private static func random(
        from alphabet: [Character], length: Int, using generator: inout SeededGenerator
    ) -> String {
        String((0..<length).map { _ in alphabet[Int(generator.next() % UInt64(alphabet.count))] })
    }

    /// Written by hand: three non-empty ASCII digit groups with single dots.
    private static func isVersion(_ text: String) -> Bool {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 3
            && parts.allSatisfy { !$0.isEmpty && $0.utf8.allSatisfy { $0 >= 48 && $0 <= 57 } }
    }

    /// Written by hand: exactly 40 lowercase hex digits.
    private static func isCommit(_ text: String) -> Bool {
        text.utf8.count == 40
            && text.utf8.allSatisfy { ($0 >= 48 && $0 <= 57) || ($0 >= 97 && $0 <= 102) }
    }

    @Test("random versions and commits never record a call unless both match the patterns exactly")
    func randomPinsOnlyPassWhenExact() throws {
        var generator = SeededGenerator()
        var accepted = 0
        var rejected = 0
        let world = try WrapperWorld()
        for round in 0..<60 {
            var version = Self.random(
                from: Self.versionAlphabet, length: Int(generator.next() % 8), using: &generator)
            var commit = Self.random(
                from: Self.commitAlphabet, length: Int(generator.next() % 4) * 14,
                using: &generator)
            // Rounds mix valid and random values so the accept path and both reject paths run.
            let validVersion =
                "\(generator.next() % 50).\(generator.next() % 50).\(generator.next() % 50)"
            let validCommit = String(String(repeating: "0123456789abcdef", count: 3).prefix(40))
            if round % 3 != 1 { version = validVersion }
            if round % 3 != 0 { commit = validCommit }
            try world.writeConfig(["version": version, "commit": commit])
            try world.installProjectBinary(contents: version + "-" + commit)
            let before = world.calls().count
            let run = try world.run(
                environment: world.baseEnvironment([
                    "ACTION": "install", "CONFIGURATION": "Release",
                ]))
            let after = world.calls().count
            if Self.isVersion(version) && Self.isCommit(commit) {
                accepted += 1
                #expect(run.status == 0, "\(version.debugDescription) \(commit.debugDescription)")
                #expect(after == before + 1)
            } else {
                rejected += 1
                #expect(run.status == 1, "\(version.debugDescription) \(commit.debugDescription)")
                #expect(after == before, "\(version.debugDescription) \(commit.debugDescription)")
            }
        }
        #expect(accepted > 3)
        #expect(rejected > 3)
    }
}
