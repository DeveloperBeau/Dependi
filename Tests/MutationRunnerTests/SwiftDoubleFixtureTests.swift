import Foundation
import Testing

/// Ties the `swift` double to the fixture package, so the double cannot drift from the real code.
@Suite("Swift double matches the fixture", .timeLimit(.minutes(1)))
struct SwiftDoubleFixtureTests {
    /// One rule line of the double.
    private struct Rule {
        let kind: String
        let key: String
        let pattern: String
    }

    private static let rules: [Rule] = SwiftDouble.rules.split(separator: "\n").map { line in
        let parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        return Rule(
            kind: parts.first ?? "", key: parts.count > 1 ? parts[1] : "",
            pattern: parts.count > 2 ? parts[2] : "")
    }

    /// The mutation that each rule pattern models, written by hand from the register entries of
    /// the runner tests. `brokenBaseline` has none: it fails on clean code, as the real test does.
    private static let mutationByPattern:
        [String: (file: String, search: String, replace: String)] = [
            "number % 2 == 1": ("Mini.swift", "number % 2 == 0", "number % 2 == 1"),
            "number != 0 &&": ("Mini.swift", "number % 2 == 0", "number != 0 && number % 2 == 0"),
            "number \\* 4": ("Other.swift", "number * 3", "number * 4"),
            "value \\+= 1": ("Mini.swift", "value -= 1", "value += 1"),
            "number % 2 ==$": ("Mini.swift", "number % 2 == 0", "number % 2 =="),
        ]

    private static let cleanSources = [
        "Mini.swift": MiniPackage.sourceText, "Other.swift": MiniPackage.otherSourceText,
    ]

    /// Matches a pattern line by line, as `grep -E` does.
    private static func matches(_ pattern: String, in text: String) throws -> Bool {
        let expression = try NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
        return expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    private static func matchesAnySource(_ pattern: String, _ sources: [String: String]) throws
        -> Bool
    {
        try sources.values.contains { try matches(pattern, in: $0) }
    }

    @Test("the double has every kind of rule and every rule has three fields")
    func rulesAreWellFormed() {
        #expect(Set(Self.rules.map(\.kind)) == ["fail", "hang", "build"])
        #expect(Self.rules.allSatisfy { !$0.key.isEmpty && !$0.pattern.isEmpty })
        #expect(Self.rules.count == 8)
    }

    @Test("no rule matches clean source except the one for brokenBaseline")
    func onlyBrokenBaselineMatchesCleanSource() throws {
        for rule in Self.rules {
            let isMatched = try Self.matchesAnySource(rule.pattern, Self.cleanSources)
            #expect(isMatched == (rule.key == "brokenBaseline\\(\\)"), "rule \(rule.pattern)")
        }
    }

    @Test("brokenBaseline fails on clean code because unusedValue returns 7, as the real test")
    func brokenBaselineModelsTheRealTest() throws {
        #expect(MiniPackage.testText.contains("#expect(unusedValue() == 0)"))
        #expect(MiniPackage.sourceText.contains("return 7"))
        let rule = try #require(Self.rules.first { $0.key == "brokenBaseline\\(\\)" })
        #expect(rule.kind == "fail")
        let fixed = MiniPackage.sourceText.replacingOccurrences(of: "return 7", with: "return 0")
        #expect(!(try Self.matches(rule.pattern, in: fixed)))
    }

    @Test("each other rule matches only after the mutation it models")
    func eachRuleMatchesAfterItsMutation() throws {
        for rule in Self.rules where rule.key != "brokenBaseline\\(\\)" {
            let mutation = try #require(
                Self.mutationByPattern[rule.pattern], "rule \(rule.pattern)")
            let clean = try #require(Self.cleanSources[mutation.file])
            #expect(clean.components(separatedBy: mutation.search).count == 2, "\(mutation.search)")
            var mutated = Self.cleanSources
            mutated[mutation.file] = clean.replacingOccurrences(
                of: mutation.search, with: mutation.replace)
            #expect(try Self.matchesAnySource(rule.pattern, mutated), "rule \(rule.pattern)")
            #expect(!(try Self.matchesAnySource(rule.pattern, Self.cleanSources)))
        }
    }

    @Test("each rule key names a test in the listing")
    func everyRuleKeyIsListed() {
        let listing = SwiftDouble.listing.split(separator: "\n").map(String.init)
        for rule in Self.rules where rule.kind != "build" {
            let name = rule.key.replacingOccurrences(of: "\\", with: "")
            #expect(
                listing.contains { $0.hasSuffix("/" + name) || $0.hasSuffix("." + name) },
                "key \(rule.key)")
        }
    }

    @Test("the listing is exactly the tests that the fixture test file declares")
    func listingMatchesFixtureTests() throws {
        var suite = ""
        var declared: [String] = []
        let suiteLine = try NSRegularExpression(pattern: #"@Suite struct (\w+)"#)
        let testLine = try NSRegularExpression(pattern: #"@Test func (\w+)\(\)"#)
        for line in MiniPackage.testText.split(separator: "\n").map(String.init) {
            let range = NSRange(line.startIndex..., in: line)
            if let match = suiteLine.firstMatch(in: line, range: range),
                let name = Range(match.range(at: 1), in: line)
            {
                suite = String(line[name])
            }
            if let match = testLine.firstMatch(in: line, range: range),
                let name = Range(match.range(at: 1), in: line)
            {
                declared.append("MiniTests.\(suite)/\(line[name])()")
            }
        }
        let listing = SwiftDouble.listing.split(separator: "\n").map(String.init)
        #expect(declared.count == 7)
        #expect(listing.sorted() == declared.sorted())
    }
}
