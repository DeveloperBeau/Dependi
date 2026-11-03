import DependiEntities
import Foundation
import TestHelpers
import Testing

@Suite("Tool configuration decoding", .timeLimit(.minutes(1)))
struct ToolConfigurationTests {
    private func decode(_ json: String) throws -> ToolConfiguration {
        try JSONDecoder().decode(ToolConfiguration.self, from: Data(json.utf8))
    }

    private let fullJSON = """
        {
          "excludes": ["app-package", "internal-kit"],
          "manualEntries": [{"name": "Vendored Lib", "licensePath": "Vendor/Lib/LICENSE"}],
          "gateConfigurations": ["Release", "AppStore"],
          "sourcePackagesPath": "ci/SourcePackages",
          "outputPath": "Settings.bundle",
          "includeBuildTools": true,
          "allowUnreached": true,
          "processTimeoutSeconds": 30,
          "runTimeoutSeconds": 120,
          "version": "1.4.2",
          "commit": "0123456789abcdef0123456789abcdef01234567"
        }
        """

    @Test("a full configuration decodes to the hand-written expected value")
    func fullConfigurationDecodes() throws {
        let expected = ToolConfiguration(
            excludes: ["app-package", "internal-kit"],
            manualEntries: [ManualEntry(name: "Vendored Lib", licensePath: "Vendor/Lib/LICENSE")],
            gateConfigurations: ["Release", "AppStore"],
            sourcePackagesPath: "ci/SourcePackages",
            outputPath: "Settings.bundle",
            includeBuildTools: true,
            allowUnreached: true,
            processTimeoutSeconds: 30,
            runTimeoutSeconds: 120,
            version: "1.4.2",
            commit: "0123456789abcdef0123456789abcdef01234567")
        #expect(try decode(fullJSON) == expected)
    }

    @Test("an empty object decodes to the documented defaults")
    func emptyObjectGivesDefaults() throws {
        let expected = ToolConfiguration(
            excludes: [],
            manualEntries: [],
            gateConfigurations: ["Release"],
            sourcePackagesPath: nil,
            outputPath: nil,
            includeBuildTools: false,
            allowUnreached: false,
            processTimeoutSeconds: 60,
            runTimeoutSeconds: 300,
            version: nil,
            commit: nil)
        #expect(try decode("{}") == expected)
    }

    @Test("a configuration survives an encode and decode round trip")
    func roundTrip() throws {
        let original = try decode(fullJSON)
        let data = try JSONEncoder().encode(original)
        #expect(try JSONDecoder().decode(ToolConfiguration.self, from: data) == original)
    }

    @Test("an unknown key fails and the error names the key")
    func unknownKeyFailsNamingTheKey() throws {
        do {
            _ = try decode(#"{"surprise": 1}"#)
            Issue.record("an unknown key was accepted")
        } catch let error as EntityError {
            #expect(error == .unknownConfigurationKey("surprise"))
        }
    }

    @Test(
        "a mistyped key fails instead of falling back to the default",
        arguments: [
            "exlcudes", "gatelist", "includeBuildtools", "Excludes", "allowunreached",
            "manualEntry",
            "gateConfiguration", "timeout", "sourcePackages", "ver",
        ])
    func mistypedKeyFails(key: String) throws {
        #expect(throws: EntityError.unknownConfigurationKey(key)) {
            try decode("{\"\(key)\": []}")
        }
    }

    @Test("every documented key is read, so none is mistaken for a typo")
    func everyDocumentedKeyIsAccepted() throws {
        for key in [
            "excludes", "manualEntries", "gateConfigurations", "sourcePackagesPath", "outputPath",
            "includeBuildTools", "allowUnreached", "processTimeoutSeconds", "runTimeoutSeconds",
            "version", "commit",
        ] {
            let json = try JSONSerialization.jsonObject(with: Data(fullJSON.utf8)) as? [String: Any]
            #expect(json?[key] != nil, "the full example lacks \(key)")
        }
        _ = try decode(fullJSON)
    }

    @Test("a wrong value type fails to decode")
    func wrongTypesFail() {
        for json in [
            #"{"excludes": "a"}"#, #"{"includeBuildTools": "yes"}"#, #"{"runTimeoutSeconds": "x"}"#,
            #"{"manualEntries": [{"name": "A"}]}"#, #"{"gateConfigurations": [1]}"#, "[]", "null",
        ] {
            #expect(throws: (any Error).self, "json: \(json)") { try decode(json) }
        }
    }

    @Test("a version of three numbers is accepted", arguments: ["0.0.0", "1.2.3", "10.20.300"])
    func goodVersionsPass(version: String) throws {
        #expect(try decode("{\"version\": \"\(version)\"}").version == version)
    }

    @Test(
        "a version that could change a path or a command is rejected",
        arguments: [
            "../../..", "1.0;rm -rf ~", "1.0.0 ", " 1.0.0", "$(id)", "", "1.2", "1.2.3.4", "v1.2.3",
            "1.2.3\n", "1.2.x", "`id`", "1.0.0/../x", "１.２.３",
        ])
    func badVersionsFail(version: String) throws {
        let escaped = version.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(
                of: "\n", with: "\\n")
        #expect(throws: EntityError.invalidVersion(version)) {
            try decode("{\"version\": \"\(escaped)\"}")
        }
    }

    @Test("a commit of 40 lowercase hex characters is accepted")
    func goodCommitPasses() throws {
        let commit = String(repeating: "ab", count: 20)
        #expect(try decode("{\"commit\": \"\(commit)\"}").commit == commit)
    }

    @Test(
        "a commit of the wrong length, case or characters is rejected",
        arguments: [
            String(repeating: "a", count: 39), String(repeating: "a", count: 41),
            String(repeating: "A", count: 40), String(repeating: "g", count: 40), "",
            String(repeating: "a", count: 39) + ";", "main",
            String(repeating: "a", count: 40) + "\n", String(repeating: "a", count: 40) + "\r\n",
        ])
    func badCommitsFail(commit: String) throws {
        #expect(throws: EntityError.invalidCommit(commit)) {
            let escaped = commit.replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "\\r")
            return try decode("{\"commit\": \"\(escaped)\"}")
        }
    }

    @Test("fuzz: random text is accepted as a version only when it is three numbers")
    func fuzzVersionAcceptedIffThreeNumbers() {
        let alphabet = Array("0123456789.vx;/ $()-")
        for seed in [SeededGenerator.defaultSeed, 7, 99, 2024] as [UInt64] {
            var generator = SeededGenerator(seed: seed)
            for _ in 0..<300 {
                let length = Int.random(in: 0...9, using: &generator)
                let text = String(
                    (0..<length).map { _ in alphabet.randomElement(using: &generator)! })
                let parts = text.split(separator: ".", omittingEmptySubsequences: false)
                let expected =
                    parts.count == 3
                    && parts.allSatisfy {
                        !$0.isEmpty && $0.allSatisfy { "0123456789".contains($0) }
                    }
                let accepted = (try? decode("{\"version\": \"\(text)\"}")) != nil
                #expect(accepted == expected, "seed \(seed) text '\(text)'")
            }
        }
    }
}
