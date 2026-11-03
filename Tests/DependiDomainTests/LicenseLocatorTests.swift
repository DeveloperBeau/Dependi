import DependiDomain
import TestHelpers
import Testing

@Suite("License locator", .timeLimit(.minutes(1)))
struct LicenseLocatorTests {
    private let locator = LicenseLocator()

    @Test("common license file names are found in a fixed order")
    func foundInFixedOrder() {
        let names = [
            "NOTICE", "LICENSE.md", "COPYING", "license", "README.md", "LICENSE-notes.txt",
            "LICENCE",
            "COPYRIGHT", "unlicense", "LICENSE-MIT", "LICENSE-APACHE.txt", "docs", "LICENSE.pdf",
            "LICENSEX", "Package.swift",
        ]
        #expect(
            locator.licenseFileNames(among: names)
                == [
                    "LICENCE", "license", "LICENSE-APACHE.txt", "LICENSE-MIT", "LICENSE.md",
                    "unlicense",
                    "COPYING", "NOTICE", "COPYRIGHT",
                ])
    }

    @Test("a NOTICE file next to a LICENSE file is found")
    func noticeNextToLicense() {
        #expect(locator.licenseFileNames(among: ["NOTICE", "LICENSE"]) == ["LICENSE", "NOTICE"])
    }

    @Test("names that only look like license files are not matched")
    func lookalikesAreNotMatched() {
        let names = [
            "LICENSE-notes.txt", "LICENSE.pdf", "LICENSEX", "my-LICENSE", "LICENSES", "docs", "",
        ]
        #expect(locator.licenseFileNames(among: names).isEmpty)
    }

    @Test("an empty list gives an empty list")
    func emptyList() {
        #expect(locator.licenseFileNames(among: []).isEmpty)
    }

    @Test("fuzz: the result does not depend on the order of the input")
    func fuzzOrderIndependent() {
        let names = [
            "LICENSE", "LICENSE.md", "License.txt", "NOTICE", "COPYING", "COPYRIGHT", "README",
            "docs",
            "LICENCE.rst", "LICENSE-MIT", "LICENSE-APACHE",
        ]
        let expected = locator.licenseFileNames(among: names)
        for seed in [SeededGenerator.defaultSeed, 12, 345] as [UInt64] {
            var generator = SeededGenerator(seed: seed)
            for _ in 0..<100 {
                #expect(
                    locator.licenseFileNames(among: names.shuffled(using: &generator)) == expected)
            }
        }
    }
}
