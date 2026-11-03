import Foundation
import Testing
import TestHelpers

@Suite("Formatter and casing lint")
struct LintTests {
    private let configuration = RepositoryRoot.url.appendingPathComponent(".swift-format")

    private func lintFixture(named fixture: String) throws -> ChildProcessResult {
        let source = RepositoryRoot.url
            .appendingPathComponent("Tests/RepositoryChecksTests/Fixtures/\(fixture).swift.txt")
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("lint-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.copyItem(
            at: source, to: directory.appendingPathComponent("\(fixture).swift"))
        return try ChildProcess.run(
            [
                "swift", "format", "lint", "--strict", "--recursive",
                "--configuration", configuration.path, directory.path,
            ],
            workingDirectory: RepositoryRoot.url)
    }

    @Test("a lowercase type name and an underscore name fail the strict lint")
    func badNamesFailLint() throws {
        let result = try lintFixture(named: "BadName")
        #expect(result.status != 0, "lint accepted bad names: \(result.output)")
        #expect(result.output.contains("lowercaseType"))
    }

    @Test("correct names pass the strict lint")
    func goodNamesPassLint() throws {
        let result = try lintFixture(named: "GoodName")
        #expect(result.status == 0, "lint rejected good names: \(result.output)")
    }

    @Test("the repository sources and tests pass the lint script")
    func repositoryPassesLint() throws {
        let result = try ChildProcess.run(
            ["sh", "Scripts/lint.sh"], workingDirectory: RepositoryRoot.url)
        #expect(result.status == 0, "lint failed: \(result.output)")
    }

    @Test("the lint script covers Sources and Tests recursively and ignores nothing")
    func lintScriptCoversEverything() throws {
        let script = try String(
            contentsOf: RepositoryRoot.url.appendingPathComponent("Scripts/lint.sh"),
            encoding: .utf8)
        #expect(script.contains("--recursive"))
        #expect(script.contains("--strict"))
        #expect(script.contains("Sources"))
        #expect(script.contains("Tests"))
        #expect(!script.contains("--ignore"))
    }

    @Test("the formatter configuration enables both casing rules")
    func configurationEnablesCasingRules() throws {
        let data = try Data(contentsOf: configuration)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let rules = try #require(json["rules"] as? [String: Bool])
        #expect(rules["AlwaysUseLowerCamelCase"] == true)
        #expect(rules["TypeNamesShouldBeCapitalized"] == true)
    }
}
