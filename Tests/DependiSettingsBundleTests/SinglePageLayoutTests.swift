import DependiDomain
import DependiEntities
import DependiTestSupport
import Foundation
import Testing
import TestHelpers

@testable import DependiSettingsBundle

@Suite("Single page layout", .timeLimit(.minutes(1)))
struct SinglePageLayoutTests {
    private let index = "\(bundle)/Acknowledgements.plist"
    private let folder = "\(bundle)/Acknowledgements"
    private let manifest = "\(bundle)/Acknowledgements/.dependi-manifest"
    /// The slugs of `alpha` and `beta()`, taken from the pane golden file.
    private let alphaPane = "\(bundle)/Acknowledgements/alpha-f4ed2b0e7b6a.plist"
    private let betaPane = "\(bundle)/Acknowledgements/beta-kit-45394b458907.plist"
    private let alpha = makeAck("Alpha", docs: [("LICENSE", "MIT")])
    private func beta(_ text: String = "Apache") -> Acknowledgement {
        makeAck("Beta Kit", location: "github.com/o/beta", docs: [("LICENSE", text)])
    }

    private func group(_ title: String, _ text: String? = nil) -> NSDictionary {
        guard let text else { return ["Type": "PSGroupSpecifier", "Title": title] }
        return ["Type": "PSGroupSpecifier", "Title": title, "FooterText": text]
    }

    private func page(_ groups: [NSDictionary]) -> NSDictionary {
        [
            "Title": "Acknowledgements", "StringsTable": "Acknowledgements",
            "PreferenceSpecifiers": groups,
        ]
    }

    // MARK: Shape

    @Test func singlePageOneDocumentPackageWritesOnlyTheIndex() throws {
        let fs = try freshFileSystem()
        let ack = makeAck("Alamofire", docs: [("LICENSE", "MIT text\n")])
        try makeSinglePageWriter(fs).write([ack], intoBundleAt: bundle)
        #expect(
            try readPlist(fs, index)
                == [
                    "Title": "Acknowledgements", "StringsTable": "Acknowledgements",
                    "PreferenceSpecifiers": [
                        [
                            "Type": "PSGroupSpecifier", "Title": "Alamofire",
                            "FooterText": "MIT text\n",
                        ]
                    ],
                ] as NSDictionary)
        #expect(!fs.exists(at: folder))
        #expect(
            try allPaths(fs) == [
                "/products", "/products/App.app", bundle, "\(bundle)/Acknowledgements.plist",
            ])
    }

    @Test func singlePageTitlesNameTheFileOnlyWhenAPackageHasSeveralDocuments() throws {
        let fs = try freshFileSystem()
        let acks = [
            makeAck("Zed", docs: [("LICENSE", "z")]),
            makeAck("Kit", docs: [("LICENSE", "a"), ("NOTICE", "b"), ("COPYING.txt", "c")]),
            makeAck("Alpha", docs: [("LICENSE.md", "m")]),
        ]
        try makeSinglePageWriter(fs).write(acks, intoBundleAt: bundle)
        #expect(
            try readPlist(fs, index)
                == page([
                    group("Zed", "z"), group("Kit (LICENSE)", "a"), group("Kit (NOTICE)", "b"),
                    group("Kit (COPYING.txt)", "c"), group("Alpha", "m"),
                ]))
    }

    @Test func singlePagePackageWithNoDocumentsKeepsATitleOnlyGroup() throws {
        let fs = try freshFileSystem()
        let acks = [makeAck("Bare", docs: []), makeAck("Kit", docs: [("LICENSE", "k")])]
        try makeSinglePageWriter(fs).write(acks, intoBundleAt: bundle)
        #expect(try readPlist(fs, index) == page([group("Bare"), group("Kit", "k")]))
    }

    @Test func singlePageKeepsTwoPackagesWithTheSameDisplayName() throws {
        let fs = try freshFileSystem()
        let acks = [
            makeAck("Kit", location: "github.com/a/kit", docs: [("LICENSE", "first")]),
            makeAck("Kit", location: "github.com/b/kit", docs: [("LICENSE", "second")]),
        ]
        try makeSinglePageWriter(fs).write(acks, intoBundleAt: bundle)
        #expect(try readPlist(fs, index) == page([group("Kit", "first"), group("Kit", "second")]))
    }

    @Test func singlePageBytesMatchTheGoldenFile() throws {
        let fs = try freshFileSystem()
        let acks = [
            makeAck(
                "Beta Kit", location: "github.com/o/beta",
                docs: [
                    ("LICENSE", "Line 1\r\n\tTabbed & <escaped>\n"),
                    ("NOTICE", "caf\u{00E9} \u{1F600}"),
                ]),
            makeAck("Alpha", docs: [("LICENSE", "MIT")]),
            makeAck("Empty", docs: []),
        ]
        try makeSinglePageWriter(fs).write(acks, intoBundleAt: bundle)
        let golden = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures").appendingPathComponent("single-page.plist.golden")
        #expect(try readBytes(fs, index) == Data(contentsOf: golden))
    }

    // MARK: Switching layouts

    @Test func switchingToSinglePageRemovesOnlyTheManifestPanesAndEmptiesTheManifest() throws {
        let fs = try freshFileSystem()
        try makeWriter(fs).write([alpha, beta()], intoBundleAt: bundle)
        try fs.addFile(at: "\(folder)/mine.txt", contents: Data("hand".utf8))
        try makeSinglePageWriter(fs).write([alpha, beta()], intoBundleAt: bundle)

        #expect(
            try readPlist(fs, index) == page([group("Alpha", "MIT"), group("Beta Kit", "Apache")]))
        #expect(!fs.exists(at: alphaPane))
        #expect(!fs.exists(at: betaPane))
        #expect(try readBytes(fs, "\(folder)/mine.txt") == Data("hand".utf8))
        #expect(try readBytes(fs, manifest).isEmpty)
        #expect(
            try allPaths(fs, under: bundle) == [
                "\(bundle)/Acknowledgements", "\(bundle)/Acknowledgements.plist",
                "\(bundle)/Acknowledgements/.dependi-manifest",
                "\(bundle)/Acknowledgements/mine.txt",
            ])
    }

    @Test func singlePageRemovesTheTemporaryLeftoversOfAnInterruptedWrite() throws {
        let fs = try freshFileSystem()
        try fs.createDirectory(at: folder)
        let leftover = "\(folder)/kit.plist.tmp-0E4C1B6A-5D3F-4B7E-9A21-6C8D2F1E3A45"
        try fs.addFile(at: leftover, contents: Data("x".utf8))
        try fs.addFile(at: "\(folder)/.DS_Store", contents: Data("junk".utf8))
        try makeSinglePageWriter(fs).write([alpha], intoBundleAt: bundle)
        #expect(try fs.topLevelNames(in: folder) == [".DS_Store", ".dependi-manifest"])
    }

    @Test func singlePageSkipsAManifestNameThatIsNoLongerInTheFolder() throws {
        let fs = try freshFileSystem()
        try fs.createDirectory(at: folder)
        try fs.addFile(at: manifest, contents: Data("gone.plist\nkept.plist\n".utf8))
        try fs.addFile(at: "\(folder)/kept.plist", contents: Data("k".utf8))
        let counter = CountingWriter(fs)
        try makeSinglePageWriter(fs, writes: counter).write([alpha], intoBundleAt: bundle)
        #expect(counter.writtenPaths == [index, "rm \(folder)/kept.plist", manifest])
    }

    @Test func switchingBackFromSinglePageWritesTheChildPanesAgain() throws {
        let fs = try freshFileSystem()
        try makeWriter(fs).write([alpha, beta()], intoBundleAt: bundle)
        try makeSinglePageWriter(fs).write([alpha, beta()], intoBundleAt: bundle)
        try makeWriter(fs).write([alpha, beta()], intoBundleAt: bundle)

        #expect(
            try readPlist(fs, index)
                == page([
                    [
                        "Type": "PSChildPaneSpecifier", "Title": "Alpha",
                        "File": "Acknowledgements/alpha-f4ed2b0e7b6a",
                    ],
                    [
                        "Type": "PSChildPaneSpecifier", "Title": "Beta Kit",
                        "File": "Acknowledgements/beta-kit-45394b458907",
                    ],
                ]))
        #expect(
            try readPlist(fs, alphaPane)
                == [
                    "Title": "Alpha", "StringsTable": "Acknowledgements",
                    "PreferenceSpecifiers": [group("LICENSE", "MIT")],
                ]
                as NSDictionary)
        #expect(
            String(decoding: try readBytes(fs, manifest), as: UTF8.self)
                == "alpha-f4ed2b0e7b6a.plist\nbeta-kit-45394b458907.plist\n")
    }

    // MARK: Order and repeat runs

    @Test func singlePageWritesTheIndexThenRemovesPanesThenWritesTheManifest() throws {
        let fs = try freshFileSystem()
        try makeWriter(fs).write([alpha, beta()], intoBundleAt: bundle)
        let counter = CountingWriter(fs)
        try makeSinglePageWriter(fs, writes: counter).write([alpha, beta()], intoBundleAt: bundle)
        #expect(counter.writtenPaths == [index, "rm \(alphaPane)", "rm \(betaPane)", manifest])
    }

    @Test func singlePageRepeatRunWritesNothing() throws {
        let fs = try freshFileSystem()
        try makeWriter(fs).write([alpha, beta()], intoBundleAt: bundle)
        try makeSinglePageWriter(fs).write([alpha, beta()], intoBundleAt: bundle)
        let counter = CountingWriter(fs)
        try makeSinglePageWriter(fs, writes: counter).write([alpha, beta()], intoBundleAt: bundle)
        #expect(counter.writtenPaths.isEmpty)
    }

    @Test func singlePageChangedTextRewritesOnlyTheIndex() throws {
        let fs = try freshFileSystem()
        try makeSinglePageWriter(fs).write([alpha, beta()], intoBundleAt: bundle)
        let counter = CountingWriter(fs)
        try makeSinglePageWriter(fs, writes: counter).write(
            [alpha, beta("changed")], intoBundleAt: bundle)
        #expect(counter.writtenPaths == [index])
        #expect(
            try readPlist(fs, index) == page([group("Alpha", "MIT"), group("Beta Kit", "changed")]))
    }

    // MARK: Failures

    @Test func singlePageRefusesALinkWhereTheFolderBelongsAndWritesNothing() throws {
        let fs = try freshFileSystem()
        try fs.addDirectory(at: "/outside")
        try fs.addFile(at: "/outside/.dependi-manifest", contents: Data("victim.plist\n".utf8))
        try fs.addFile(at: "/outside/victim.plist", contents: Data("v".utf8))
        try fs.addSymlink(at: folder, pointingTo: "/outside")
        let before = try allPaths(fs)
        let counter = CountingWriter(fs)
        #expect(
            throws: DomainError.fileUnwritable(
                path: folder, reason: "it is a link, and Dependi does not write through links")
        ) {
            try makeSinglePageWriter(fs, writes: counter).write([alpha], intoBundleAt: bundle)
        }
        #expect(counter.writtenPaths.isEmpty)
        #expect(try allPaths(fs) == before)
        #expect(try readBytes(fs, "/outside/victim.plist") == Data("v".utf8))
    }

    @Test func singlePageNulInALicenseTextFailsBeforeAnyWriteOrRemoval() throws {
        let fs = try freshFileSystem()
        try makeWriter(fs).write([alpha], intoBundleAt: bundle)
        let before = try allPaths(fs)
        let counter = CountingWriter(fs)
        #expect(
            throws: DomainError.fileUnwritable(path: index, reason: "the pane cannot be encoded")
        ) {
            try makeSinglePageWriter(fs, writes: counter).write(
                [alpha, beta("a\0b")], intoBundleAt: bundle)
        }
        #expect(counter.writtenPaths.isEmpty)
        #expect(try allPaths(fs) == before)
    }

    @Test func singlePageReadOnlyBundleFailsWithFileUnwritable() throws {
        let fs = try freshFileSystem()
        fs.markReadOnly(bundle)
        do {
            try makeSinglePageWriter(fs).write([alpha], intoBundleAt: bundle)
            Issue.record("expected a failure")
        } catch {
            guard case .fileUnwritable = error else {
                Issue.record("wrong error \(error)")
                return
            }
        }
        #expect(!fs.exists(at: index))
    }

    @Test func singlePageReadBackMismatchFails() throws {
        let fs = try freshFileSystem()
        let writer = makeSinglePageWriter(fs, reader: AlteringReader(inner: fs))
        #expect(
            throws: DomainError.fileUnwritable(
                path: index, reason: "the file read back differs from what was written")
        ) {
            try writer.write([alpha], intoBundleAt: bundle)
        }
    }

    // MARK: Fuzz

    @Test func singlePageFuzzKeepsEveryLicenseInOrderAndRefusesEveryNul() throws {
        let alphabet: [Character] = Array(
            "abcXYZ019 ./\\\n\r\t\u{0C}&<>\"'\u{00E9}\u{4E2D}\u{1F600}\u{200D}-_")
        for seed in [SeededGenerator.defaultSeed, 3, 1_234, 0xBEEF] as [UInt64] {
            var rng = SeededGenerator(seed: seed)
            func random(_ maxLength: Int) -> String {
                String(
                    (0..<Int.random(in: 0...maxLength, using: &rng)).map { _ in
                        alphabet.randomElement(using: &rng)!
                    })
            }
            for round in 0..<30 {
                let label = "seed \(seed) round \(round)"
                let acks = (0..<Int.random(in: 0...6, using: &rng)).map { i in
                    makeAck(
                        random(20), location: "h\(i)/x",
                        docs: (0..<Int.random(in: 0...3, using: &rng)).map {
                            ("F\($0)", random(300))
                        }
                    )
                }
                // False negatives: every package and document appears once, in order, unchanged.
                var expected: [NSDictionary] = []
                for ack in acks {
                    if ack.documents.isEmpty { expected.append(group(ack.displayName)) }
                    for document in ack.documents {
                        let title =
                            ack.documents.count == 1
                            ? ack.displayName : ack.displayName + " (" + document.fileName + ")"
                        expected.append(group(title, document.text))
                    }
                }
                let fs = try freshFileSystem()
                try makeSinglePageWriter(fs).write(acks, intoBundleAt: bundle)
                #expect(try readPlist(fs, index) == page(expected), "\(label)")
                #expect(!fs.exists(at: folder), "\(label)")

                // False positives: a NUL anywhere in one text is always refused with no write.
                guard let target = acks.indices.first(where: { !acks[$0].documents.isEmpty })
                else { continue }
                var poisoned = acks
                let text = acks[target].documents[0].text
                let cut = Int.random(in: 0...text.count, using: &rng)
                let bad = String(text.prefix(cut)) + "\0" + String(text.dropFirst(cut))
                poisoned[target] = makeAck(
                    acks[target].displayName, location: "h\(target)/x",
                    docs: [("F0", bad)]
                        + acks[target].documents.dropFirst().map { ($0.fileName, $0.text) })
                let counter = CountingWriter(fs)
                #expect(throws: DomainError.self, "\(label)") {
                    try makeSinglePageWriter(fs, writes: counter).write(
                        poisoned, intoBundleAt: bundle)
                }
                #expect(counter.writtenPaths.isEmpty, "\(label)")
            }
        }
    }
}
