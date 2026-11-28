import Foundation
import Testing
import TestHelpers

@Suite("Forbidden content in repository files", .timeLimit(.minutes(5)))
struct ForbiddenContentTests {
    private func makeTemporaryTree(files: [String: String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("forbidden-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for (name, text) in files {
            let url = root.appendingPathComponent(name)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        return root
    }

    @Test("a planted user home path is found")
    func plantedUserPathIsFound() throws {
        let planted = "/Us" + "ers/someone/project"
        let root = try makeTemporaryTree(files: ["a.txt": "path \(planted)"])
        defer { try? FileManager.default.removeItem(at: root) }
        let found = try ForbiddenContentScanner.scan(root: root, relativePaths: ["a.txt"])
        #expect(found == [.init(relativePath: "a.txt", fragment: "/Us" + "ers/")])
    }

    @Test("a planted linux home path is found")
    func plantedHomePathIsFound() throws {
        let planted = "/ho" + "me/someone/project"
        let root = try makeTemporaryTree(files: ["b.txt": planted])
        defer { try? FileManager.default.removeItem(at: root) }
        let found = try ForbiddenContentScanner.scan(root: root, relativePaths: ["b.txt"])
        #expect(found == [.init(relativePath: "b.txt", fragment: "/ho" + "me/")])
    }

    @Test("a configured extra fragment is found")
    func extraFragmentIsFound() throws {
        let root = try makeTemporaryTree(files: ["c.txt": "written by Example Person"])
        defer { try? FileManager.default.removeItem(at: root) }
        let found = try ForbiddenContentScanner.scan(
            root: root, relativePaths: ["c.txt"], extraFragments: ["Example Person"])
        #expect(found == [.init(relativePath: "c.txt", fragment: "Example Person")])
    }

    @Test("words that only resemble a home path are not flagged")
    func similarWordsAreNotFlagged() throws {
        let root = try makeTemporaryTree(files: [
            "d.txt": "Users guide, the home page, a relative path like Users/name or home/name"
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        let found = try ForbiddenContentScanner.scan(root: root, relativePaths: ["d.txt"])
        #expect(found.isEmpty)
    }

    @Test("a missing file is skipped without failing the scan")
    func missingFileIsSkipped() throws {
        let root = try makeTemporaryTree(files: [:])
        defer { try? FileManager.default.removeItem(at: root) }
        let found = try ForbiddenContentScanner.scan(root: root, relativePaths: ["absent.txt"])
        #expect(found.isEmpty)
    }

    @Test("the repository holds no home path and no git user name")
    func repositoryIsClean() throws {
        let root = RepositoryRoot.url
        let files = try ForbiddenContentScanner.listCandidateFiles(root: root)
        let name = try ChildProcess.run(["git", "config", "user.name"], workingDirectory: root)
            .output.trimmingCharacters(in: .whitespacesAndNewlines)
        let extra = name.count >= 3 ? [name] : []
        let found = try ForbiddenContentScanner.scan(
            root: root, relativePaths: files, extraFragments: extra, copyrightFile: "NOTICE")
        #expect(found.isEmpty, "forbidden content: \(found)")
    }

    @Test("the holder name on the exact copyright line of NOTICE is accepted")
    func noticeCopyrightLineIsAccepted() throws {
        let texts = [
            "Dependi\nCopyright 2026 Example Person\n\nLicence line",
            "Dependi\nCopyright 2024-2026 Example Person\n\nLicence line",
            "Dependi\r\nCopyright 2026 Example Person\r\n\r\nLicence line\r\n",
        ]
        for text in texts {
            #expect(try scanNotice(text).isEmpty, "text \(text.debugDescription)")
        }
    }

    @Test("the holder name on another line of NOTICE is flagged")
    func nameOnAnotherNoticeLineIsFlagged() throws {
        let texts = [
            "Dependi\nCopyright 2026 Example Person\nWritten by Example Person\n",
            "Dependi\nExample Person\n",
        ]
        for text in texts {
            #expect(
                try scanNotice(text) == [.init(relativePath: "NOTICE", fragment: holder)],
                "text \(text.debugDescription)")
        }
    }

    @Test("the copyright line in any file other than NOTICE is flagged")
    func copyrightLineInAnotherFileIsFlagged() throws {
        for name in ["README.md", "NOTICE.md", "sub/NOTICE"] {
            let root = try makeTemporaryTree(files: [name: "Copyright 2026 Example Person\n"])
            defer { try? FileManager.default.removeItem(at: root) }
            let found = try ForbiddenContentScanner.scan(
                root: root, relativePaths: [name], extraFragments: [holder],
                copyrightFile: "NOTICE")
            #expect(found == [.init(relativePath: name, fragment: holder)], "file \(name)")
        }
    }

    @Test("a copyright line with anything extra is flagged")
    func copyrightLineWithAnythingExtraIsFlagged() throws {
        let lines = [
            "Copyright 2026 Example Person Jr", "Copyright 2026 Not Example Person",
            "Copyright 2026 Example Person and others", " Copyright 2026 Example Person",
            "copyright 2026 Example Person", "Copyright Example Person",
            "Copyright 2026 Example Person.", "Copyright (c) 2026 Example Person",
            "Copyright 20x6 Example Person", "Copyright 2026Example Person",
            "Copyright 2026-Example Person", "Copyright 2026\tExample Person",
            "Copyright 2026Example Person.", "Copyright 2026  Example Person",
            "Copyright\t2026 Example Person",
        ]
        for line in lines {
            #expect(
                try scanNotice("Dependi\n\(line)\n")
                    == [.init(relativePath: "NOTICE", fragment: holder)],
                "line \(line.debugDescription)")
        }
    }

    @Test("a holder made of digits is judged by the same rules")
    func digitHolderIsJudgedByTheSameRules() throws {
        let digits = "1999"
        for line in ["Copyright 1999-1999x", "Copyright 1999-1999"] {
            #expect(
                try scanNotice("Dependi\n\(line)\n", holder: digits)
                    == [.init(relativePath: "NOTICE", fragment: digits)],
                "line \(line.debugDescription)")
        }
        for line in ["Copyright 2026 1999", "Copyright 1999 1999"] {
            #expect(
                try scanNotice("Dependi\n\(line)\n", holder: digits).isEmpty,
                "line \(line.debugDescription)")
        }
    }

    @Test("the copyright years must be one year or an ordered range")
    func copyrightYearsMustBeOneYearOrAnOrderedRange() throws {
        let accepted = [
            "Copyright 2026 Example Person", "Copyright 2024-2026 Example Person",
            "Copyright 2026-2026 Example Person",
        ]
        for line in accepted {
            #expect(try scanNotice("Dependi\n\(line)\n").isEmpty, "line \(line.debugDescription)")
        }
        let flagged = [
            "Copyright - Example Person", "Copyright 2026- Example Person",
            "Copyright -2026 Example Person", "Copyright 2026-2025 Example Person",
            "Copyright 26 Example Person", "Copyright 20260 Example Person",
            "Copyright 2026-26 Example Person", "Copyright 2026-20260 Example Person",
            "Copyright 2026--2027 Example Person", "Copyright 2026-2027-2028 Example Person",
            "Copyright 2026,2027 Example Person", "Copyright 2026 2027 Example Person",
            "Copyright \u{0662}\u{0660}\u{0662}\u{0666} Example Person",
            "Copyright \u{FF12}\u{FF10}\u{FF12}\u{FF16} Example Person",
        ]
        for line in flagged {
            #expect(
                try scanNotice("Dependi\n\(line)\n")
                    == [.init(relativePath: "NOTICE", fragment: holder)],
                "line \(line.debugDescription)")
        }
    }

    @Test("two valid copyright lines in NOTICE are both accepted")
    func twoValidCopyrightLinesAreBothAccepted() throws {
        let first = "Copyright 2025 Example Person"
        let second = "Copyright 2026 Example Person"
        let third = "Copyright 2020-2024 Example Person"
        let texts = [
            "Dependi\n\(first)\nLicence line\n\(second)\n",
            "Dependi\n\(first)\n\(second)\n",
            "Dependi\r\n\(first)\r\n\(second)\r\nLicence line\r\n",
            "Dependi\n\(first)\n\(second)\nLicence line\n\(third)\n",
        ]
        for text in texts {
            #expect(try scanNotice(text).isEmpty, "text \(text.debugDescription)")
        }
    }

    @Test("a broken copyright line next to a valid one is flagged")
    func aValidLineThenABrokenCopyrightLineIsFlagged() throws {
        let valid = "Copyright 2026 Example Person"
        let broken = "Copyright 2026 Example Person Jr"
        let texts = [
            "Dependi\n\(valid)\n\(broken)\n",
            "Dependi\n\(broken)\n\(valid)\n",
            "Dependi\n\(valid)\n\(broken)\n\(valid)\n",
        ]
        for text in texts {
            #expect(
                try scanNotice(text) == [.init(relativePath: "NOTICE", fragment: holder)],
                "text \(text.debugDescription)")
        }
    }

    @Test("a home path in NOTICE is found even with the copyright exemption")
    func homePathStillFoundInNoticeWithExemption() throws {
        for home in ForbiddenContentScanner.homeDirectoryFragments {
            let planted = "Dependi\nCopyright 2026 Example Person\nSee \(home)someone/notes\n"
            #expect(
                try scanNotice(planted) == [.init(relativePath: "NOTICE", fragment: home)],
                "text \(planted.debugDescription)")
            let root = try makeTemporaryTree(files: ["NOTICE": "Copyright 2026 \(home)\n"])
            defer { try? FileManager.default.removeItem(at: root) }
            let found = try ForbiddenContentScanner.scan(
                root: root, relativePaths: ["NOTICE"], extraFragments: [home],
                copyrightFile: "NOTICE")
            #expect(
                found.contains(.init(relativePath: "NOTICE", fragment: home)),
                "holder \(home.debugDescription)")
        }
    }

    @Test("without a copyright file the holder name in NOTICE is flagged")
    func noticeWithoutCopyrightFileSettingFlagsTheName() throws {
        let root = try makeTemporaryTree(files: [
            "NOTICE": "Dependi\nCopyright 2026 Example Person\n\nLicence line"
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        let found = try ForbiddenContentScanner.scan(
            root: root, relativePaths: ["NOTICE"], extraFragments: [holder])
        #expect(found == [.init(relativePath: "NOTICE", fragment: holder)])
    }

    @Test("fuzz: a valid copyright line in NOTICE is never flagged")
    func fuzzValidCopyrightLinesAreAccepted() throws {
        for seed in [SeededGenerator.defaultSeed, 11, 42, 9001] as [UInt64] {
            var generator = SeededGenerator(seed: seed)
            for _ in 0..<300 {
                let name = randomHolder(using: &generator)
                let text = randomNotice(holder: name, using: &generator)
                let found = try scanNotice(text, holder: name)
                #expect(found.isEmpty, "seed \(seed) text \(text.debugDescription)")
            }
        }
    }

    @Test("fuzz: a broken copyright line or a second mention is always flagged")
    func fuzzBrokenCopyrightLinesAreFlagged() throws {
        for seed in [SeededGenerator.defaultSeed, 11, 42, 9001] as [UInt64] {
            var generator = SeededGenerator(seed: seed)
            for _ in 0..<300 {
                let name = randomHolder(using: &generator)
                let years = randomYears(using: &generator)
                let line = "Copyright \(years) \(name)"
                var file = "NOTICE"
                var broken = line
                let corruption = Int.random(in: 0..<8, using: &generator)
                switch corruption {
                case 0:
                    broken = randomWord(using: &generator) + " " + line
                case 1:
                    broken = line + randomSuffix(using: &generator)
                case 2:
                    let word = ["copyright", "COPYRIGHT", "CopyRight", "copyRight"]
                    broken = line.replacingOccurrences(
                        of: "Copyright", with: word.randomElement(using: &generator)!)
                case 3:
                    broken = "Copyright \(name)"
                case 4:
                    file = ["README.md", "NOTICE.md", "LICENSE", "notice", "NOTICE.txt"]
                        .randomElement(using: &generator)!
                case 5:
                    let separator = ["", "-", "\t"].randomElement(using: &generator)!
                    broken = "Copyright " + years + separator + name
                case 6:
                    let badYears = [
                        "", "-", "20", "202", "20260", "2026-", "-2026", "2026-2025", "2026-26",
                        "26-2026", "2026--2027", "abcd", "2O26",
                    ]
                    broken = "Copyright \(badYears.randomElement(using: &generator)!) \(name)"
                default:
                    broken = line + "\n" + randomWord(using: &generator) + " " + name
                }
                let text = "Dependi\n\(broken)\nLicence line\n"
                let root = try makeTemporaryTree(files: [file: text])
                defer { try? FileManager.default.removeItem(at: root) }
                let found = try ForbiddenContentScanner.scan(
                    root: root, relativePaths: [file], extraFragments: [name],
                    copyrightFile: "NOTICE")
                #expect(
                    found == [.init(relativePath: file, fragment: name)],
                    "seed \(seed) case \(corruption) file \(file) \(text.debugDescription)")
            }
        }
    }

    private let holder = "Example Person"

    private func scanNotice(_ text: String, holder name: String? = nil) throws
        -> [ForbiddenContentScanner.Violation]
    {
        let root = try makeTemporaryTree(files: ["NOTICE": text])
        defer { try? FileManager.default.removeItem(at: root) }
        return try ForbiddenContentScanner.scan(
            root: root, relativePaths: ["NOTICE"], extraFragments: [name ?? holder],
            copyrightFile: "NOTICE")
    }

    private func randomLetters(
        count: Int, using generator: inout SeededGenerator
    ) -> String {
        let letters = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")
        return String((0..<count).map { _ in letters.randomElement(using: &generator)! })
    }

    private func randomHolder(using generator: inout SeededGenerator) -> String {
        let words = (0..<Int.random(in: 1...3, using: &generator)).map { _ in
            randomLetters(count: Int.random(in: 3...8, using: &generator), using: &generator)
        }
        return words.joined(separator: " ")
    }

    private func randomYears(using generator: inout SeededGenerator) -> String {
        let start = Int.random(in: 1990...2030, using: &generator)
        if Bool.random(using: &generator) { return String(start) }
        return "\(start)-\(start + Int.random(in: 1...10, using: &generator))"
    }

    private func randomWord(using generator: inout SeededGenerator) -> String {
        ["Written by", "Thanks to", "(c)", "Maintained by", "Contact"]
            .randomElement(using: &generator)!
    }

    private func randomSuffix(using generator: inout SeededGenerator) -> String {
        [".", " Jr", " and others", " ", ",", " (c)"].randomElement(using: &generator)!
    }

    /// Builds NOTICE text with one or two valid copyright lines among lines that never hold the holder.
    private func randomNotice(holder name: String, using generator: inout SeededGenerator) -> String
    {
        let harmless = [
            "Dependi", "", "This product is licensed under the Apache License, Version 2.0.",
            "See the LICENSE file.", "2026",
        ]
        var lines = (0..<Int.random(in: 0...6, using: &generator)).map { _ in
            let candidate = harmless.randomElement(using: &generator)!
            return candidate.contains(name) ? randomDigits(using: &generator) : candidate
        }
        let years = randomYears(using: &generator)
        lines.insert(
            "Copyright \(years) \(name)", at: Int.random(in: 0...lines.count, using: &generator))
        if Bool.random(using: &generator) {
            var otherYears = randomYears(using: &generator)
            while otherYears == years { otherYears = randomYears(using: &generator) }
            lines.insert(
                "Copyright \(otherYears) \(name)",
                at: Int.random(in: 0...lines.count, using: &generator))
        }
        let separator = Bool.random(using: &generator) ? "\r\n" : "\n"
        return lines.joined(separator: separator)
            + (Bool.random(using: &generator) ? separator : "")
    }

    private func randomDigits(using generator: inout SeededGenerator) -> String {
        String(Int.random(in: 0...99_999, using: &generator))
    }
}
