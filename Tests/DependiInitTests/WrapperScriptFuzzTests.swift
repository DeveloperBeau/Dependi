import Foundation
import TestHelpers
import Testing

@Suite("Wrapper script fuzz", .timeLimit(.minutes(5)))
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
        let seed = generator.seed
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
                #expect(
                    run.status == 0,
                    "seed \(seed) round \(round): \(version.debugDescription) \(commit.debugDescription)"
                )
                #expect(after == before + 1)
            } else {
                rejected += 1
                #expect(
                    run.status == 1,
                    "seed \(seed) round \(round): \(version.debugDescription) \(commit.debugDescription)"
                )
                #expect(
                    after == before,
                    "seed \(seed) round \(round): \(version.debugDescription) \(commit.debugDescription)"
                )
            }
        }
        #expect(accepted > 3)
        #expect(rejected > 3)
    }

    private static let claimAlphabet = Array("0123456789abcXYZ-/. ;$`\n")

    /// A claim target that is not a process id. Written by hand: it has at least one character that
    /// is neither a digit nor a line break, so the script cannot read it as a number or as empty.
    private static func malformedClaim(using generator: inout SeededGenerator) -> String {
        var text = random(
            from: claimAlphabet, length: 1 + Int(generator.next() % 8), using: &generator)
        if !text.contains(where: { !$0.isNumber && $0 != "\n" }) { text += "x" }
        return text
    }

    @Test("a claim is respected only when a running process holds it and it is fresh")
    func randomClaimsAreRespectedOnlyWhenLiveAndFresh() throws {
        var generator = SeededGenerator()
        let seed = generator.seed
        var respected = 0
        var cleared = 0
        for round in 0..<24 {
            let world = try WrapperWorld()
            let head = try world.makeOrigin()
            try world.writeConfig(["version": "1.2.3", "commit": head])
            let dead = String(try world.deadProcessIdentifier())
            try world.plantLock(version: "1.2.3", commit: head, owner: dead)
            let kind = round % 3
            let target: String
            switch kind {
            case 0: target = String(getpid())
            case 1: target = String(try world.deadProcessIdentifier())
            default: target = Self.malformedClaim(using: &generator)
            }
            try world.plantClaim(version: "1.2.3", commit: head, target: target)
            let run = try world.run(
                environment: world.buildEnvironment(["DEPENDI_LOCK_WAIT_STEPS": "3"]))
            let note = "seed \(seed) round \(round): claim \(target.debugDescription)"
            if kind == 0 {
                respected += 1
                #expect(run.status == 1, "\(note)")
                #expect(world.calls().isEmpty, "\(note)")
                #expect(world.lockOwner(version: "1.2.3", commit: head) == dead, "\(note)")
                #expect(world.claimTarget(version: "1.2.3", commit: head) == target, "\(note)")
            } else {
                cleared += 1
                #expect(run.status == 0, "\(note): \(run.stderr)")
                #expect(world.calls(of: "xcrun").count == 1, "\(note)")
                #expect(world.cacheEntries() == ["1.2.3-\(head)"], "\(note)")
            }
        }
        #expect(respected > 3)
        #expect(cleared > 3)
    }
}
