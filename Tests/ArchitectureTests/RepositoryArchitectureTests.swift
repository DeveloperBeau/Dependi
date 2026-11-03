import CryptoKit
import Foundation
import Testing

@Suite("Repository architecture")
struct RepositoryArchitectureTests {
    private let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private func recordedDump() throws -> PackageDump {
        let url = root.appendingPathComponent("Tests/ArchitectureTests/Fixtures/package-dump.json")
        return try PackageDump.parse(Data(contentsOf: url))
    }

    private func productionSources() throws -> [SourceFile] {
        let sourcesRoot = root.appendingPathComponent("Sources")
        let modules = try FileManager.default.contentsOfDirectory(
            at: sourcesRoot, includingPropertiesForKeys: [.isDirectoryKey])
        var files: [SourceFile] = []
        for module in modules
        where (try? module.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            let enumerator = FileManager.default.enumerator(
                at: module, includingPropertiesForKeys: nil)
            while let url = enumerator?.nextObject() as? URL {
                guard url.pathExtension == "swift" else { continue }
                let text = try String(contentsOf: url, encoding: .utf8)
                files.append(
                    SourceFile(
                        module: module.lastPathComponent, name: url.lastPathComponent, text: text))
            }
        }
        return files
    }

    @Test("the recorded package dump matches Package.swift")
    func recordedDumpIsCurrent() throws {
        let manifest = try Data(contentsOf: root.appendingPathComponent("Package.swift"))
        let actual = SHA256.hash(data: manifest).map { String(format: "%02x", $0) }.joined()
        let recorded = try String(
            contentsOf: root.appendingPathComponent(
                "Tests/ArchitectureTests/Fixtures/package-dump.sha256"),
            encoding: .utf8
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(actual == recorded, "Package.swift changed. Run Scripts/refresh-package-dump.sh")
    }

    @Test("the recorded package dump holds no machine path")
    func recordedDumpHasNoRootPath() throws {
        let text = try String(
            contentsOf: root.appendingPathComponent(
                "Tests/ArchitectureTests/Fixtures/package-dump.json"),
            encoding: .utf8)
        #expect(text.contains("$ROOT"))
        for fragment in ["/Us" + "ers/", "/ho" + "me/"] {
            #expect(!text.contains(fragment))
        }
    }

    @Test("the repository satisfies every architecture rule")
    func repositoryHoldsTheArchitecture() throws {
        let found = ArchitectureChecker.check(
            dump: try recordedDump(), sources: try productionSources())
        #expect(found.isEmpty, "\(found.map(\.description).joined(separator: "\n"))")
    }

    @Test("the gate script runs lint, tests and the per-module build")
    func gateScriptCoversEveryCheck() throws {
        let gate = try String(
            contentsOf: root.appendingPathComponent("Scripts/gate.sh"), encoding: .utf8)
        for step in [
            "Scripts/lint.sh", "Scripts/refresh-package-dump.sh",
            "git diff --exit-code -- Tests/ArchitectureTests/Fixtures", "swift test",
            "Scripts/build-each-target.sh",
        ] {
            #expect(gate.contains(step), "the gate does not run \(step)")
        }
    }

    @Test(
        "the per-module build script builds each module with its own scratch path and a time limit")
    func moduleBuildScriptIsolatesEachModule() throws {
        let script = try String(
            contentsOf: root.appendingPathComponent("Scripts/build-each-target.sh"), encoding: .utf8
        )
        #expect(script.contains("--target"))
        #expect(script.contains("--scratch-path"))
        #expect(script.contains("alarm"))
    }
}
