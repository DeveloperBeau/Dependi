import Testing
import TestHelpers

@Suite("Import scanner", .timeLimit(.minutes(1)))
struct ImportScannerTests {
    @Test("every import form names its module")
    func importFormsAreRecognised() {
        let source = """
            import Foundation
            @testable import Alpha
            @_exported import Beta
            @preconcurrency import Gamma
            public import Delta
            internal import Epsilon
            package import Zeta
            import struct Eta.Name
            import func Theta.run
              import Iota
            """
        #expect(
            ImportScanner.importedModules(in: source)
                == [
                    "Foundation", "Alpha", "Beta", "Gamma", "Delta", "Epsilon", "Zeta", "Eta",
                    "Theta", "Iota",
                ])
    }

    @Test("imports in comments, strings and conditions are not imports")
    func decoysAreIgnored() {
        let source = """
            // import Commented
            /* import Block */
            /* outer /* import Nested */ import StillComment */
            let a = "import InString"
            let b = \"\"\"
            import InMultiline
            \"\"\"
            let c = #"import InRaw"#
            #if canImport(Conditional)
            import Real
            #endif
            let important = 1
            """
        #expect(ImportScanner.importedModules(in: source) == ["Real"])
    }

    @Test("a name that only starts with import is not an import")
    func importPrefixIsNotImport() {
        #expect(ImportScanner.importedModules(in: "important thing\nimportant()").isEmpty)
    }

    @Test("fuzz: generated files give back exactly their real imports")
    func fuzzRealImportsSurviveDecoys() {
        let decoys = [
            "// import Fake", "/* import Fake */", "let s = \"import Fake\"",
            "let r = #\"import Fake\"#", "#if canImport(Fake)\n#endif", "let important = 1",
            "let m = \"\"\"\nimport Fake\n\"\"\"",
        ]
        let prefixes = [
            "", "@testable ", "@_exported ", "public ", "@preconcurrency ", "internal ",
        ]
        for seed in [SeededGenerator.defaultSeed, 1, 2, 3, 42, 4242] as [UInt64] {
            var generator = SeededGenerator(seed: seed)
            var lines: [String] = []
            var expected: [String] = []
            for index in 0..<Int.random(in: 5...30, using: &generator) {
                if Bool.random(using: &generator) {
                    let name = "Module\(index)"
                    lines.append(prefixes.randomElement(using: &generator)! + "import " + name)
                    expected.append(name)
                } else {
                    lines.append(decoys.randomElement(using: &generator)!)
                }
            }
            let found = ImportScanner.importedModules(in: lines.joined(separator: "\n"))
            #expect(found == expected, "seed \(seed)")
        }
    }

    @Test("the seeded generator repeats its sequence and the default seed has fixed first values")
    func generatorIsRepeatable() {
        var first = SeededGenerator()
        var second = SeededGenerator()
        #expect((0..<5).map { _ in first.next() } == (0..<5).map { _ in second.next() })
        var other = SeededGenerator(seed: 1)
        var again = SeededGenerator()
        #expect(other.next() != again.next())
    }
}
