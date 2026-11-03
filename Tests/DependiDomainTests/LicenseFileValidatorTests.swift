import DependiDomain
import DependiEntities
import DependiTestSupport
import Foundation
import TestHelpers
import Testing

@Suite("License file validator")
struct LicenseFileValidatorTests {
    private func setup() throws -> InMemoryFileSystem {
        let files = InMemoryFileSystem()
        try files.addDirectory(at: "/checkouts/kit")
        try files.addFile(
            at: "/checkouts/kit/LICENSE", contents: Data("MIT License\n\tText\r\n".utf8))
        return files
    }

    private func validator(_ files: InMemoryFileSystem, limit: Int = 100) -> LicenseFileValidator {
        LicenseFileValidator(files: files, maximumBytes: limit)
    }

    private func document(_ files: InMemoryFileSystem, name: String = "LICENSE", limit: Int = 100)
        throws(DomainError) -> LicenseDocument
    {
        try validator(files, limit: limit).document(
            named: name, inFolder: "/checkouts/kit", root: "/checkouts/kit", owner: "kit")
    }

    @Test("a plain license file is read with tabs and line breaks kept")
    func plainFile() throws {
        let result = try document(try setup())
        #expect(result.fileName == "LICENSE")
        #expect(result.text == "MIT License\n\tText\r\n")
    }

    @Test("a link that stays inside the package is accepted")
    func insideLinkAccepted() throws {
        let files = try setup()
        try files.addSymlink(at: "/checkouts/kit/COPYING", pointingTo: "/checkouts/kit/LICENSE")
        #expect(try document(files, name: "COPYING").text == "MIT License\n\tText\r\n")
    }

    @Test("a link that leaves the package is refused")
    func outsideLinkRefused() throws {
        let files = try setup()
        try files.addFile(at: "/secrets", contents: Data("secret".utf8))
        try files.addSymlink(at: "/checkouts/kit/NOTICE", pointingTo: "/secrets")
        #expect(throws: DomainError.licenseOutsideCheckout(package: "kit", file: "NOTICE")) {
            try document(files, name: "NOTICE")
        }
    }

    @Test("a link into a sibling folder with a similar name is refused")
    func similarSiblingRefused() throws {
        let files = try setup()
        try files.addDirectory(at: "/checkouts/kit-evil")
        try files.addFile(at: "/checkouts/kit-evil/LICENSE", contents: Data("evil".utf8))
        try files.addSymlink(at: "/checkouts/kit/NOTICE", pointingTo: "/checkouts/kit-evil/LICENSE")
        #expect(
            throws: DomainError.licenseOutsideCheckout(
                package: "kit", file: "NOTICE")
        ) {
            try document(files, name: "NOTICE")
        }
    }

    @Test("a package reached through a linked parent folder is still contained")
    func linkedRootIsContained() throws {
        let files = InMemoryFileSystem()
        try files.addDirectory(at: "/private/var/checkouts/kit")
        try files.addSymlink(at: "/var", pointingTo: "/private/var")
        try files.addFile(at: "/var/checkouts/kit/LICENSE", contents: Data("text".utf8))
        let result = try LicenseFileValidator(files: files, maximumBytes: 100).document(
            named: "LICENSE", inFolder: "/var/checkouts/kit", root: "/var/checkouts/kit",
            owner: "kit")
        #expect(result.text == "text")
    }

    @Test("exactly the limit is accepted and one byte more is refused")
    func sizeBoundary() throws {
        let files = try setup()
        try files.addFile(at: "/checkouts/kit/NOTICE", contents: Data(repeating: 65, count: 10))
        try files.addFile(at: "/checkouts/kit/COPYING", contents: Data(repeating: 65, count: 11))
        #expect(try document(files, name: "NOTICE", limit: 10).text.count == 10)
        #expect(throws: DomainError.licenseTooLarge(package: "kit", file: "COPYING")) {
            try document(files, name: "COPYING", limit: 10)
        }
    }

    @Test("a folder, a pipe and a missing file are refused with their own errors")
    func specialFiles() throws {
        let files = try setup()
        try files.addDirectory(at: "/checkouts/kit/NOTICE")
        try files.addNamedPipe(at: "/checkouts/kit/COPYING")
        #expect(throws: DomainError.notRegularFile(path: "/checkouts/kit/NOTICE")) {
            try document(files, name: "NOTICE")
        }
        #expect(throws: DomainError.notRegularFile(path: "/checkouts/kit/COPYING")) {
            try document(files, name: "COPYING")
        }
        #expect(throws: DomainError.fileNotFound(path: "/checkouts/kit/ABSENT")) {
            try document(files, name: "ABSENT")
        }
    }

    @Test("text in UTF-16 with a byte order mark is decoded")
    func utf16Accepted() throws {
        let files = try setup()
        let data = Data([0xFF, 0xFE]) + "Hi".data(using: .utf16LittleEndian)!
        try files.addFile(at: "/checkouts/kit/NOTICE", contents: data)
        #expect(try document(files, name: "NOTICE").text == "Hi")
    }

    @Test("bytes that are not valid text are refused and name the file")
    func badEncodingRefused() throws {
        let files = try setup()
        try files.addFile(at: "/checkouts/kit/NOTICE", contents: Data([0xC3, 0x28, 0xFF]))
        #expect(throws: DomainError.licenseEncoding(package: "kit", file: "NOTICE")) {
            try document(files, name: "NOTICE")
        }
    }

    @Test("a control character other than tab, line feed and carriage return is refused")
    func controlCharactersRefused() throws {
        let files = try setup()
        for (index, byte) in ([0x00, 0x01, 0x08, 0x0B, 0x0C, 0x1B, 0x1F] as [UInt8]).enumerated() {
            try files.addFile(at: "/checkouts/kit/N\(index)", contents: Data([65, byte, 66]))
            #expect(throws: DomainError.licenseControlCharacter(package: "kit", file: "N\(index)"))
            {
                try document(files, name: "N\(index)")
            }
        }
    }

    @Test(
        "fuzz: random bytes are accepted if and only if they are valid text without control characters"
    )
    func fuzzBytes() throws {
        let files = try setup()
        for seed in [SeededGenerator.defaultSeed, 4, 40] as [UInt64] {
            var generator = SeededGenerator(seed: seed)
            for index in 0..<150 {
                let count = Int.random(in: 0...12, using: &generator)
                let bytes = Data(
                    (0..<count).map { _ in UInt8.random(in: 0...255, using: &generator) })
                try files.addFile(at: "/checkouts/kit/F\(index)", contents: bytes)
                var expectedOK = false
                if !(bytes.starts(with: [0xFF, 0xFE]) || bytes.starts(with: [0xFE, 0xFF])),
                    let text = String(data: bytes, encoding: .utf8)
                {
                    expectedOK = !text.unicodeScalars.contains {
                        $0.value < 0x20 && ![9, 10, 13].contains($0.value)
                    }
                }
                let accepted = (try? document(files, name: "F\(index)")) != nil
                if !(bytes.starts(with: [0xFF, 0xFE]) || bytes.starts(with: [0xFE, 0xFF])) {
                    #expect(accepted == expectedOK, "seed \(seed) bytes \(Array(bytes))")
                }
            }
        }
    }
}
