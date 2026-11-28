import DependiDomain
import Foundation
import Testing

@testable import DependiProjectFile

@Suite("Project text scanner", .timeLimit(.minutes(1)))
struct PBXTextScannerTests {
    private func scan(_ text: String) throws -> PBXTextScanner {
        try PBXTextScanner(bytes: Array(text.utf8), path: "/p")
    }

    private static let wrap = "// !$*UTF8*$!\n{\n\tobjects = {\n%@\t};\n\trootObject = A;\n}\n"

    private func project(_ body: String) -> String {
        Self.wrap.replacingOccurrences(of: "%@", with: body)
    }

    @Test("an escaped quote inside a string does not end it")
    func escapedQuote() throws {
        let scanner = try scan(
            project("\t\tA = {\n\t\t\tname = \"a\\\"}b\";\n\t\t\tother = c;\n\t\t};\n"))
        let object = try #require(scanner.object("A"))
        let keys = try scanner.entries(ofDictionaryAt: object.valueFirst).map(\.key)
        #expect(keys == ["name", "other"])
        let name = try #require(try scanner.entry("name", inDictionaryAt: object.valueFirst))
        #expect(scanner.text(name.valueFirst) == "a\"}b")
    }

    @Test("a brace or a key inside a comment is ignored")
    func braceInComment() throws {
        let scanner = try scan(
            project(
                "\t\tA = {\n\t\t\t/* } name = x; */\n\t\t\t// { more = y;\n\t\t\tkey = v;\n\t\t};\n"
            ))
        let object = try #require(scanner.object("A"))
        #expect(try scanner.entries(ofDictionaryAt: object.valueFirst).map(\.key) == ["key"])
    }

    @Test("an object is found by id at depth two only")
    func objectDepth() throws {
        let text =
            "{\n\tA = {\n\t\tisa = Top;\n\t};\n\tobjects = {\n\t\tB = {\n\t\t\tA = {\n\t\t\t};\n\t\t};\n\t};\n}\n"
        let scanner = try scan(text)
        #expect(scanner.object("A") == nil)
        #expect(scanner.object("B") != nil)
    }

    @Test("section markers give the offsets of their lines")
    func sections() throws {
        let body =
            "/* Begin PBXBuildFile section */\n\t\tA = {\n\t\t};\n/* End PBXBuildFile section */\n"
        let text = project(body)
        let scanner = try scan(text)
        let section = try #require(scanner.sections().first)
        #expect(section.isa == "PBXBuildFile")
        let bytes = Array(text.utf8)
        #expect(
            String(
                decoding: bytes[section.begin..<scanner.lineEnd(of: section.begin)], as: UTF8.self)
                == "/* Begin PBXBuildFile section */\n")
        #expect(
            String(decoding: bytes[section.end..<scanner.lineEnd(of: section.end)], as: UTF8.self)
                == "/* End PBXBuildFile section */\n")
    }

    @Test("a list gives the start of each item and tabs before a span")
    func listsAndTabs() throws {
        let scanner = try scan(
            project("\t\tA = {\n\t\t\tlist = (\n\t\t\t\tx /* c */,\n\t\t\t\ty,\n\t\t\t);\n\t\t};\n")
        )
        let object = try #require(scanner.object("A"))
        let list = try #require(try scanner.entry("list", inDictionaryAt: object.valueFirst))
        let starts = try scanner.itemStarts(ofListAt: list.valueFirst)
        #expect(starts.map { scanner.text($0) } == ["x", "y"])
        #expect(scanner.tabsBefore(span: starts[0]) == "\t\t\t\t")
        #expect(scanner.tabsBefore(span: list.valueFirst) == nil)
    }

    @Test(
        "text that is not a well formed project fails",
        arguments: [
            "{ objects = { A = \"open; }; }",
            "{ objects = { /* open }; }",
            "{ objects = { A = { }; }",
            "{ objects = { A = { }; }; } }",
            "( objects )",
            "{ a = b; }",
            "{ objects = { A = b }; }",
            "{ objects = { A = { x = ; }; }; }",
            "{ objects = { A = ( }; }; }",
            "{ objects = { }; } x",
        ])
    func malformed(_ text: String) {
        #expect(throws: DomainError.self) {
            let scanner = try scan(text)
            // An inner dictionary is checked when it is read.
            if let object = scanner.object("A") {
                _ = try scanner.entries(ofDictionaryAt: object.valueFirst)
            }
        }
    }
}
