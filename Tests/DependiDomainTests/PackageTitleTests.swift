import DependiDomain
import DependiEntities
import TestHelpers
import Testing

@Suite("Package title", .timeLimit(.minutes(1)))
struct PackageTitleTests {
    private let identity = PackageIdentity("sqlite.swift")

    private func title(
        _ name: String?, version: String? = "0.16.0", isRemote: Bool = true
    ) -> String {
        PackageTitle().title(
            manifestName: name, identity: identity, version: version, isRemote: isRemote)
    }

    @Test("a remote package with a version reads name then version in brackets")
    func nameAndVersion() {
        #expect(title("SQLite.swift") == "SQLite.swift (0.16.0)")
    }

    @Test("a missing, empty or blank version gives the name alone")
    func noVersion() {
        #expect(title("KeychainSwift", version: nil) == "KeychainSwift")
        #expect(title("KeychainSwift", version: "") == "KeychainSwift")
        #expect(title("KeychainSwift", version: "  \u{A0} ") == "KeychainSwift")
    }

    @Test("white space around the name and the version is trimmed")
    func trims() {
        #expect(title("  RevenueCat \u{A0}", version: " 5.1.0  ") == "RevenueCat (5.1.0)")
    }

    @Test("a nil, empty or blank name falls back to the identity")
    func nameFallsBack() {
        #expect(title(nil) == "sqlite.swift (0.16.0)")
        #expect(title("") == "sqlite.swift (0.16.0)")
        #expect(title("   ") == "sqlite.swift (0.16.0)")
        #expect(title(nil, version: nil) == "sqlite.swift")
    }

    @Test("a name with a control character falls back to the identity")
    func controlCharacterInName() {
        for bad in ["Kit\u{0}", "Ki\tt", "Kit\n", "\u{1B}[31mKit", "Kit\u{7F}", "Ki\u{85}t"] {
            #expect(title(bad) == "sqlite.swift (0.16.0)", "name \(bad.debugDescription)")
        }
    }

    @Test("a version with a control character is left out")
    func controlCharacterInVersion() {
        #expect(title("Kit", version: "1.0\n.0") == "Kit")
    }

    @Test("a local package never shows a version")
    func localIgnoresVersion() {
        #expect(title("Core", version: "9.9.9", isRemote: false) == "Core")
        #expect(title(nil, version: "9.9.9", isRemote: false) == "sqlite.swift")
    }

    @Test("a name with brackets, unicode or inner spaces is kept as it is")
    func awkwardNamesKept() {
        #expect(title("Kit (beta)") == "Kit (beta) (0.16.0)")
        #expect(title("Ünï Çødé 日本") == "Ünï Çødé 日本 (0.16.0)")
        #expect(title("Two  spaces") == "Two  spaces (0.16.0)")
    }

    @Test("random names and versions give the right title in both directions")
    func fuzz() {
        var generator = SeededGenerator()
        print("package title fuzz seed: \(generator.seed)")
        let pieces = ["a", "Z", "9", "é", "日", " ", "(", ")", ".", "-", "_", "\u{A0}"]
        let controls = ["\u{0}", "\u{1}", "\t", "\n", "\r", "\u{1B}", "\u{7F}", "\u{85}", "\u{9F}"]
        var used = 0
        var rejected = 0
        for round in 0..<2000 {
            var body = (0..<Int.random(in: 1...8, using: &generator)).map { _ in
                pieces.randomElement(using: &generator)!
            }
            // Pad with the characters that the trim removes, and keep one real character inside.
            body.append("k")
            let core = body.joined()
            let lead = String(repeating: " ", count: Int.random(in: 0...2, using: &generator))
            let tail = String(repeating: "\u{A0}", count: Int.random(in: 0...2, using: &generator))
            let padded = lead + core + tail
            let trimmed = trim(padded)
            let versions = ["1.2.3", "", "  ", "2.0.0-beta.1", " 3.0 "]
            let version = versions.randomElement(using: &generator)!
            let isRemote = Bool.random(using: &generator)

            // False negative check: every valid name is used, after the trim.
            let good = PackageTitle().title(
                manifestName: padded, identity: identity, version: version, isRemote: isRemote)
            let cleanVersion = trim(version)
            let suffix = isRemote && !cleanVersion.isEmpty ? " (\(cleanVersion))" : ""
            #expect(good == trimmed + suffix, "round \(round) seed \(generator.seed)")
            used += 1

            // False positive check: a name with a control character anywhere is never used.
            var scalars = Array(padded)
            scalars.insert(
                Character(controls.randomElement(using: &generator)!),
                at: Int.random(in: 0...scalars.count, using: &generator))
            let bad = PackageTitle().title(
                manifestName: String(scalars), identity: identity, version: version,
                isRemote: isRemote)
            #expect(bad == "sqlite.swift" + suffix, "round \(round) seed \(generator.seed)")
            rejected += 1
        }
        #expect(used == 2000 && rejected == 2000)
    }

    private func trim(_ text: String) -> String {
        var scalars = Substring(text)
        while let first = scalars.first, first == " " || first == "\u{A0}" { scalars.removeFirst() }
        while let last = scalars.last, last == " " || last == "\u{A0}" { scalars.removeLast() }
        return String(scalars)
    }
}
