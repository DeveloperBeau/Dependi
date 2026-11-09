import DependiEntities
import TestHelpers
import Testing

@Suite("License document names", .timeLimit(.minutes(1)))
struct LicenseDocumentTests {
    @Test(
        "plain file names are accepted",
        arguments: [
            "LICENSE", "LICENSE.md", "COPYING", "NOTICE", "LICENSE-MIT", "..a", "a..",
            "L\u{00ED}cence",
            "許可証", "LICENSE.txt",
        ])
    func plainNamesAreAccepted(name: String) throws {
        let document = try LicenseDocument(fileName: name, text: "text")
        #expect(document.fileName == name)
    }

    @Test(
        "names with a path separator, an empty name or a dot name are rejected",
        arguments: [
            "", ".", "..", "a/b", "/etc/passwd", "../LICENSE", "dir\\file", "LICENSE/", "a\u{0}b",
            "a\nb",
            "a\u{7F}",
        ])
    func unsafeNamesAreRejected(name: String) {
        #expect(throws: EntityError.invalidLicenseFileName(name)) {
            try LicenseDocument(fileName: name, text: "text")
        }
    }

    @Test("the text is kept exactly, including blank lines and control characters")
    func textIsKeptExactly() throws {
        let text = "line one\n\n\tindented\r\nend\u{0}"
        #expect(try LicenseDocument(fileName: "LICENSE", text: text).text == text)
    }

    @Test(
        "fuzz: a name is accepted if and only if it holds no separator, control character or dot name"
    )
    func fuzzNameAcceptance() {
        let alphabet = Array("abAB.-_/\\\u{0}\n é")
        for seed in [SeededGenerator.defaultSeed, 5, 77, 31337] as [UInt64] {
            var generator = SeededGenerator(seed: seed)
            for _ in 0..<400 {
                let length = Int.random(in: 0...6, using: &generator)
                let name = String(
                    (0..<length).map { _ in alphabet.randomElement(using: &generator)! })
                let unsafe =
                    name.isEmpty || name == "." || name == ".." || name.contains("/")
                    || name.contains("\\")
                    || name.unicodeScalars.contains { $0.value < 0x20 || $0.value == 0x7F }
                let accepted = (try? LicenseDocument(fileName: name, text: "")) != nil
                #expect(accepted == !unsafe, "seed \(seed) name \(name.debugDescription)")
            }
        }
    }
}
