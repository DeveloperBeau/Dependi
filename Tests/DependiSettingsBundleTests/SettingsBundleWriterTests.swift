import DependiDomain
import DependiEntities
import DependiTestSupport
import Foundation
import Testing
import TestHelpers

@testable import DependiSettingsBundle

@Suite struct SettingsBundleWriterTests {
    // MARK: Shape

    @Test func singleDocumentPackageWritesIndexChildAndManifest() throws {
        let fs = try freshFileSystem()
        let ack = makeAck("Alamofire", docs: [("LICENSE", "MIT text\n")])
        try makeWriter(fs).write([ack], intoBundleAt: bundle)
        let slug = slugOf(ack)

        let index = try readPlist(fs, "\(bundle)/Acknowledgements.plist")
        let expectedIndex: NSDictionary = [
            "Title": "Acknowledgements",
            "StringsTable": "Acknowledgements",
            "PreferenceSpecifiers": [
                [
                    "Type": "PSChildPaneSpecifier", "Title": "Alamofire",
                    "File": "Acknowledgements/\(slug)",
                ]
            ],
        ]
        #expect(index == expectedIndex)

        let child = try readPlist(fs, "\(bundle)/Acknowledgements/\(slug).plist")
        let expectedChild: NSDictionary = [
            "Title": "Alamofire",
            "StringsTable": "Acknowledgements",
            "PreferenceSpecifiers": [
                ["Type": "PSGroupSpecifier", "Title": "LICENSE", "FooterText": "MIT text\n"]
            ],
        ]
        #expect(child == expectedChild)
        let manifest = try readBytes(fs, "\(bundle)/Acknowledgements/.dependi-manifest")
        #expect(String(decoding: manifest, as: UTF8.self) == "\(slug).plist\n")
    }

    @Test func multiDocumentPackageGivesOneGroupPerDocumentInOrder() throws {
        let fs = try freshFileSystem()
        let ack = makeAck("Kit", docs: [("LICENSE", "a"), ("NOTICE", "b"), ("COPYING.txt", "c")])
        try makeWriter(fs).write([ack], intoBundleAt: bundle)
        let child = try readPlist(fs, "\(bundle)/Acknowledgements/\(slugOf(ack)).plist")
        let expected: NSDictionary = [
            "Title": "Kit", "StringsTable": "Acknowledgements",
            "PreferenceSpecifiers": [
                ["Type": "PSGroupSpecifier", "Title": "LICENSE", "FooterText": "a"],
                ["Type": "PSGroupSpecifier", "Title": "NOTICE", "FooterText": "b"],
                ["Type": "PSGroupSpecifier", "Title": "COPYING.txt", "FooterText": "c"],
            ],
        ]
        #expect(child == expected)
    }

    @Test func indexKeepsTheGivenOrder() throws {
        let fs = try freshFileSystem()
        let acks = [makeAck("Zed"), makeAck("Alpha"), makeAck("Mid")]
        try makeWriter(fs).write(acks, intoBundleAt: bundle)
        let index = try readPlist(fs, "\(bundle)/Acknowledgements.plist")
        let entries = try #require(index["PreferenceSpecifiers"] as? [[String: String]])
        #expect(entries.map { $0["Title"] } == ["Zed", "Alpha", "Mid"])
        #expect(entries.map { $0["File"] } == acks.map { "Acknowledgements/" + slugOf($0) })
    }

    @Test(arguments: [
        "line1\r\nline2\r\n", "tab\there\t\t", "emoji \u{1F600} and \u{00E9} and \u{4E2D}\u{6587}",
        "a & b < c > d \"q\" 'r'", "", "trailing space   \n\n\n",
    ])
    func textSurvivesByteForByte(text: String) throws {
        let fs = try freshFileSystem()
        let ack = makeAck("T", docs: [("LICENSE", text)])
        try makeWriter(fs).write([ack], intoBundleAt: bundle)
        let child = try readPlist(fs, "\(bundle)/Acknowledgements/\(slugOf(ack)).plist")
        let groups = try #require(child["PreferenceSpecifiers"] as? [[String: String]])
        #expect(Array((groups[0]["FooterText"] ?? "?").utf8) == Array(text.utf8))
    }

    @Test func hundredKilobyteTextSurvives() throws {
        let fs = try freshFileSystem()
        let line = "Permission is hereby granted, free of charge.\t\u{00E9}\r\n"
        let text = String(repeating: line, count: 100_000 / line.utf8.count + 1)
        let ack = makeAck("Big", docs: [("LICENSE", text)])
        try makeWriter(fs).write([ack], intoBundleAt: bundle)
        let child = try readPlist(fs, "\(bundle)/Acknowledgements/\(slugOf(ack)).plist")
        let groups = try #require(child["PreferenceSpecifiers"] as? [[String: String]])
        #expect(groups[0]["FooterText"] == text)
    }

    // MARK: Names

    @Test(arguments: [
        "../x", "a/b", "", String(repeating: "long-", count: 200), "caf\u{00E9}",
        "line\nbreak", "\u{1F680}rocket", "..", "/etc/passwd",
    ])
    func oddNamesStayInsideTheFolderAndAppearOnlyAsText(name: String) throws {
        let fs = try freshFileSystem()
        let ack = Acknowledgement(
            displayName: name, identity: PackageIdentity(name), normalizedLocation: "host/" + name,
            documents: [try LicenseDocument(fileName: "LICENSE", text: "t")])
        try makeWriter(fs).write([ack], intoBundleAt: bundle)
        let paths = try allPaths(fs).filter { $0.hasPrefix("/products/App.app/Settings.bundle") }
        let children = paths.filter { $0.hasSuffix(".plist") && $0.contains("/Acknowledgements/") }
        #expect(children.count == 1)
        for path in paths {
            #expect(!path.dropFirst(bundle.count).contains(".."))
        }
        let fileName = String(children[0].split(separator: "/").last!)
        #expect(fileName.range(of: "^[a-z0-9_-]+\\.plist$", options: .regularExpression) != nil)
        let child = try readPlist(fs, children[0])
        #expect(child["Title"] as? String == name)
    }

    @Test func nameWithNulFailsBeforeAnyWrite() throws {
        let fs = try freshFileSystem()
        let counter = CountingWriter(fs)
        let ack = makeAck("a\0b")
        #expect(throws: DomainError.self) {
            try makeWriter(fs, writes: counter).write([ack], intoBundleAt: bundle)
        }
        #expect(counter.writtenPaths.isEmpty)
        #expect(try allPaths(fs) == ["/products", "/products/App.app", bundle])
    }

    @Test func nothingIsWrittenOutsideTheBundle() throws {
        let fs = try freshFileSystem()
        let before = try allPaths(fs)
        let acks = ["../x", "a/b", ""].map { makeAck($0, location: "h/" + $0) }
        try makeWriter(fs).write(acks, intoBundleAt: bundle)
        let added = Set(try allPaths(fs)).subtracting(before)
        #expect(!added.isEmpty)
        #expect(added.allSatisfy { $0.hasPrefix(bundle + "/") })
    }

    @Test(arguments: [
        "/products/App.app/Settings.bundle", "/products/App.app/Contents/Resources/Settings.bundle",
        "/products/App.app/Settings.bundle/",
        "/products/XR.app/Settings.bundle",
    ])
    func writesOnlyUnderTheGivenBundlePath(path: String) throws {
        let fs = InMemoryFileSystem()
        try fs.createDirectory(at: path)
        try fs.createDirectory(at: "/products/Other.app/Settings.bundle")
        let before = Set(try allPaths(fs))
        let ack = makeAck("Kit")
        try makeWriter(fs).write([ack], intoBundleAt: path)
        let root = path.hasSuffix("/") ? String(path.dropLast()) : path
        let added = Set(try allPaths(fs)).subtracting(before)
        #expect(added.count == 4)
        #expect(added.allSatisfy { $0.hasPrefix(root + "/") })
        #expect(added.contains("\(root)/Acknowledgements.plist"))
        #expect(added.contains("\(root)/Acknowledgements/\(slugOf(ack)).plist"))
    }

    // MARK: Determinism

    @Test func outputBytesMatchTheGoldenFile() throws {
        let fs = try freshFileSystem()
        let acks = [
            makeAck(
                "Beta Kit", location: "github.com/o/beta",
                docs: [
                    ("LICENSE", "Line 1\r\n\tTabbed & <escaped>\n"),
                    ("NOTICE", "caf\u{00E9} \u{1F600}"),
                ]),
            makeAck("Alpha", location: "github.com/o/alpha", docs: [("LICENSE", "MIT")]),
        ]
        try makeWriter(fs).write(acks, intoBundleAt: bundle)
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
        let expectedIndex = try Data(
            contentsOf: directory.appendingPathComponent("index.plist.golden"))
        let expectedChild = try Data(
            contentsOf: directory.appendingPathComponent("child.plist.golden"))
        #expect(try readBytes(fs, "\(bundle)/Acknowledgements.plist") == expectedIndex)
        #expect(
            try readBytes(fs, "\(bundle)/Acknowledgements/\(slugOf(acks[0])).plist")
                == expectedChild)

        let again = try freshFileSystem()
        try makeWriter(again).write(acks, intoBundleAt: bundle)
        #expect(try readBytes(again, "\(bundle)/Acknowledgements.plist") == expectedIndex)
    }

    @Test func secondIdenticalRunWritesNothing() throws {
        let fs = try freshFileSystem()
        let acks = [makeAck("A"), makeAck("B")]
        try makeWriter(fs).write(acks, intoBundleAt: bundle)
        let counter = CountingWriter(fs)
        try makeWriter(fs, writes: counter).write(acks, intoBundleAt: bundle)
        #expect(counter.writtenPaths.isEmpty)
        #expect(counter.removedPaths.isEmpty)
    }

    @Test func changedLicenseUpdatesOnlyThatFile() throws {
        let fs = try freshFileSystem()
        let a = makeAck("A"), b = makeAck("B")
        try makeWriter(fs).write([a, b], intoBundleAt: bundle)
        let counter = CountingWriter(fs)
        let changed = makeAck("B", docs: [("LICENSE", "new text")])
        try makeWriter(fs, writes: counter).write([a, changed], intoBundleAt: bundle)
        #expect(counter.writtenPaths == ["\(bundle)/Acknowledgements/\(slugOf(b)).plist"])
    }

    // MARK: Cleanup and ownership

    @Test func removedPackageRemovesItsPlistAndManifestEntry() throws {
        let fs = try freshFileSystem()
        let a = makeAck("A"), b = makeAck("B")
        try makeWriter(fs).write([a, b], intoBundleAt: bundle)
        try makeWriter(fs).write([a], intoBundleAt: bundle)
        #expect(!fs.exists(at: "\(bundle)/Acknowledgements/\(slugOf(b)).plist"))
        #expect(fs.exists(at: "\(bundle)/Acknowledgements/\(slugOf(a)).plist"))
        let manifest = try readBytes(fs, "\(bundle)/Acknowledgements/.dependi-manifest")
        #expect(String(decoding: manifest, as: UTF8.self) == "\(slugOf(a)).plist\n")
    }

    @Test func manifestIsSortedOneNamePerLine() throws {
        let fs = try freshFileSystem()
        let acks = ["Q", "C", "X", "B"].map { makeAck($0) }
        try makeWriter(fs).write(acks, intoBundleAt: bundle)
        let expected = acks.map { slugOf($0) + ".plist" }.sorted().joined(separator: "\n") + "\n"
        let manifest = try readBytes(fs, "\(bundle)/Acknowledgements/.dependi-manifest")
        #expect(String(decoding: manifest, as: UTF8.self) == expected)
    }

    @Test func emptyListWritesEmptyIndexAndRemovesStalePlists() throws {
        let fs = try freshFileSystem()
        let a = makeAck("A")
        try makeWriter(fs).write([a], intoBundleAt: bundle)
        try makeWriter(fs).write([], intoBundleAt: bundle)
        let index = try readPlist(fs, "\(bundle)/Acknowledgements.plist")
        let expected: NSDictionary = [
            "Title": "Acknowledgements", "StringsTable": "Acknowledgements",
            "PreferenceSpecifiers": [String](),
        ]
        #expect(index == expected)
        #expect(try fs.topLevelNames(in: "\(bundle)/Acknowledgements") == [".dependi-manifest"])
        #expect(try readBytes(fs, "\(bundle)/Acknowledgements/.dependi-manifest").isEmpty)
    }

    @Test func unknownFileInFolderFailsBeforeAnyWrite() throws {
        let fs = try freshFileSystem()
        try fs.createDirectory(at: "\(bundle)/Acknowledgements")
        try fs.addFile(at: "\(bundle)/Acknowledgements/mine.plist", contents: Data("hand".utf8))
        let before = try allPaths(fs)
        let counter = CountingWriter(fs)
        #expect(
            throws: DomainError.fileUnwritable(
                path: "\(bundle)/Acknowledgements/mine.plist",
                reason: "a file that Dependi did not write is in the way")
        ) {
            try makeWriter(fs, writes: counter).write([makeAck("A")], intoBundleAt: bundle)
        }
        #expect(counter.writtenPaths.isEmpty)
        #expect(try allPaths(fs) == before)
        #expect(try readBytes(fs, "\(bundle)/Acknowledgements/mine.plist") == Data("hand".utf8))
    }

    @Test func fileListedInThePreviousManifestIsNotUnknown() throws {
        let fs = try freshFileSystem()
        let a = makeAck("A")
        try makeWriter(fs).write([a], intoBundleAt: bundle)
        // Another run with the same package must pass: its own files are known.
        try makeWriter(fs).write([a], intoBundleAt: bundle)
        #expect(fs.exists(at: "\(bundle)/Acknowledgements/\(slugOf(a)).plist"))
    }

    @Test func userMadeIndexPlistIsOverwritten() throws {
        let fs = try freshFileSystem()
        try fs.addFile(at: "\(bundle)/Acknowledgements.plist", contents: Data("old".utf8))
        try makeWriter(fs).write([makeAck("A")], intoBundleAt: bundle)
        let index = try readPlist(fs, "\(bundle)/Acknowledgements.plist")
        #expect(index["Title"] as? String == "Acknowledgements")
    }

    @Test func staleCleanupDeletesOnlyManifestListedFiles() throws {
        let fs = try freshFileSystem()
        let a = makeAck("A"), b = makeAck("B")
        try makeWriter(fs).write([a, b], intoBundleAt: bundle)
        try fs.addFile(at: "\(bundle)/Root.plist", contents: Data("root".utf8))
        try fs.addFile(at: "\(bundle)/en.lproj-note", contents: Data("n".utf8))
        let counter = CountingWriter(fs)
        try makeWriter(fs, writes: counter).write([a], intoBundleAt: bundle)
        #expect(counter.removedPaths == ["rm \(bundle)/Acknowledgements/\(slugOf(b)).plist"])
        #expect(try readBytes(fs, "\(bundle)/Root.plist") == Data("root".utf8))
        #expect(fs.exists(at: "\(bundle)/en.lproj-note"))
    }

    @Test func manifestEntriesThatEscapeTheFolderAreNeverDeleted() throws {
        let fs = try freshFileSystem()
        try fs.createDirectory(at: "\(bundle)/Acknowledgements")
        try fs.addFile(at: "\(bundle)/Root.plist", contents: Data("root".utf8))
        let evil = "../Root.plist\n/x.plist\n..\\y.plist\n"
        try fs.addFile(
            at: "\(bundle)/Acknowledgements/.dependi-manifest", contents: Data(evil.utf8))
        try makeWriter(fs).write([], intoBundleAt: bundle)
        #expect(fs.exists(at: "\(bundle)/Root.plist"))
    }

    // MARK: Failures

    @Test func readOnlyBundleFailsWithFileUnwritable() throws {
        let fs = try freshFileSystem()
        fs.markReadOnly(bundle)
        #expect(throws: DomainError.self) {
            try makeWriter(fs).write([makeAck("A")], intoBundleAt: bundle)
        }
        do {
            try makeWriter(fs).write([makeAck("A")], intoBundleAt: bundle)
            Issue.record("expected a failure")
        } catch {
            guard case .fileUnwritable = error else {
                Issue.record("wrong error \(error)")
                return
            }
        }
    }

    @Test func readBackMismatchFailsWithFileUnwritable() throws {
        let fs = try freshFileSystem()
        let writer = makeWriter(fs, reader: AlteringReader(inner: fs))
        do {
            try writer.write([makeAck("A")], intoBundleAt: bundle)
            Issue.record("expected a failure")
        } catch {
            guard case .fileUnwritable(let path, let reason) = error else {
                Issue.record("wrong error \(error)")
                return
            }
            #expect(path.hasSuffix(".plist"))
            #expect(reason.contains("read back"))
        }
    }

    @Test func honestReaderPassesReadBack() throws {
        let fs = try freshFileSystem()
        try makeWriter(fs).write([makeAck("A")], intoBundleAt: bundle)
    }

    @Test func duplicateSlugsFailBeforeAnyWrite() throws {
        let fs = try freshFileSystem()
        let counter = CountingWriter(fs)
        let a = makeAck("A")
        #expect(throws: DomainError.self) {
            try makeWriter(fs, writes: counter).write([a, a], intoBundleAt: bundle)
        }
        #expect(counter.writtenPaths.isEmpty)
    }

    // MARK: Fuzz

    @Test func fuzzRandomNamesAndTextsRoundTripAndStayInside() throws {
        var rng = SeededGenerator(seed: 0x5E77_1465)
        let alphabet: [Character] = Array(
            "abcXYZ019 ./\\..\n\t\r&<>\"'\u{00E9}\u{4E2D}\u{1F600}-_:;%$#@!~")
        func random(_ maxLength: Int) -> String {
            String(
                (0..<Int.random(in: 0...maxLength, using: &rng)).map { _ in
                    alphabet.randomElement(using: &rng)!
                })
        }
        for round in 0..<40 {
            let fs = try freshFileSystem()
            let before = Set(try allPaths(fs))
            let acks = (0..<Int.random(in: 0...6, using: &rng)).map { i in
                let name = random(30)
                return Acknowledgement(
                    displayName: name, identity: PackageIdentity(name),
                    normalizedLocation: "h\(i)/" + random(20),
                    documents: (0..<Int.random(in: 0...3, using: &rng)).map { j in
                        try! LicenseDocument(fileName: "F\(j)", text: random(400))
                    })
            }
            try makeWriter(fs).write(acks, intoBundleAt: bundle)
            let added = Set(try allPaths(fs)).subtracting(before)
            #expect(added.allSatisfy { $0.hasPrefix(bundle + "/") }, "seed round \(round)")
            for ack in acks {
                let child = try readPlist(fs, "\(bundle)/Acknowledgements/\(slugOf(ack)).plist")
                let groups = try #require(child["PreferenceSpecifiers"] as? [[String: String]])
                #expect(child["Title"] as? String == ack.displayName, "seed round \(round)")
                #expect(groups.map { $0["FooterText"] } == ack.documents.map { $0.text })
                #expect(groups.map { $0["Title"] } == ack.documents.map { $0.fileName })
            }
        }
    }
}
