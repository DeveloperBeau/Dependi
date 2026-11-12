import Foundation
import Testing
import TestHelpers

@Suite("Tracked build output", .timeLimit(.minutes(1)))
struct TrackedBuildOutputTests {
    private let scratchFolders: Set<String> = [".build", ".build-modules"]

    private let decoys = [
        ".Build", ".BUILD", ".build-modules-backup", "build", ".building",
        "BuildContext.swift", ".build.swift", "not.build", "module.build-modules",
        ".swiftpm", "Sources", "file.o", "out", "DependiDomain", ".build-modules.txt",
    ]

    @Test("a planted scratch path is build output")
    func plantedScratchPathIsBuildOutput() {
        let planted = [
            (".build-modules/DependiDomain/out/file.pcm", ".build-modules"),
            (".build/debug/dependi", ".build"),
            ("Contract/.build/checkouts/pkg", ".build"),
            (".build-modules", ".build-modules"),
            (".build", ".build"),
            (".build/a\"b.o", ".build"),
            (".build/ü.o", ".build"),
        ]
        for (path, folder) in planted {
            let found = TrackedBuildOutput.violations(in: [path])
            #expect(
                found == [.init(relativePath: path, directoryName: folder)],
                "path \(path)"
            )
        }
    }

    @Test("a path that only resembles a scratch folder is kept")
    func similarNamesAreKept() {
        let found = TrackedBuildOutput.violations(in: [
            "Sources/DependiEntities/BuildContext.swift",
            "Documentation/build-modules.md",
            ".build-modules-backup/cache.o",
            "Sources/not.build/File.swift",
            ".Build/cache.o",
            ".swiftpm/config",
            ".build-modules.txt",
            "module.build-modules/file.o",
        ])
        #expect(found.isEmpty)
    }

    @Test("the first scratch folder in a path is the one reported")
    func firstScratchFolderWins() {
        let path = ".build/checkouts/.build-modules/file.o"
        let found = TrackedBuildOutput.violations(in: [path])
        #expect(found == [.init(relativePath: path, directoryName: ".build")])
    }

    @Test("violations keep the order of the tracked paths")
    func violationsKeepPathOrder() {
        let found = TrackedBuildOutput.violations(in: [
            "Package.swift",
            ".build-modules/a.o",
            "Sources/DependiEntities/BuildContext.swift",
            "Contract/.build/debug/dependi",
        ])
        #expect(
            found == [
                .init(relativePath: ".build-modules/a.o", directoryName: ".build-modules"),
                .init(relativePath: "Contract/.build/debug/dependi", directoryName: ".build"),
            ]
        )
    }

    @Test("an empty path list has no build output")
    func emptyListIsClean() {
        #expect(TrackedBuildOutput.violations(in: []).isEmpty)
    }

    @Test("fuzz: a path with no scratch folder component is kept")
    func fuzzLookalikePathsAreKept() {
        for seed in [SeededGenerator.defaultSeed, 11, 42, 9001] as [UInt64] {
            var generator = SeededGenerator(seed: seed)
            for _ in 0..<400 {
                let path = randomPath(using: &generator, plant: nil)
                let found = TrackedBuildOutput.violations(in: [path])
                #expect(found.isEmpty, "seed \(seed) path \(path)")
                #expect(expectedFolder(in: path) == nil, "seed \(seed) path \(path)")
            }
        }
    }

    @Test("fuzz: a path with a scratch folder component is build output")
    func fuzzScratchFolderPathsAreBuildOutput() {
        for seed in [SeededGenerator.defaultSeed, 11, 42, 9001] as [UInt64] {
            var generator = SeededGenerator(seed: seed)
            for _ in 0..<400 {
                let folder = scratchFolders.randomElement(using: &generator)!
                let path = randomPath(using: &generator, plant: folder)
                let expected = expectedFolder(in: path)
                let found = TrackedBuildOutput.violations(in: [path])
                #expect(expected == folder, "seed \(seed) path \(path)")
                #expect(
                    found == [.init(relativePath: path, directoryName: folder)],
                    "seed \(seed) path \(path)"
                )
            }
        }
    }

    @Test("a scratch file with a quote or a non-ascii name is build output")
    func quotedScratchFileIsBuildOutput() throws {
        let root = try makeScratchIndex()
        defer { try? FileManager.default.removeItem(at: root) }
        let listed = try TrackedBuildOutput.listTrackedPaths(root: root)
        #expect(listed.contains(".build/a\"b.o"))
        #expect(listed.contains(".build/ü.o"))
        #expect(listed.contains("Sources/Keep.swift"))
        let found = TrackedBuildOutput.violations(in: listed)
        #expect(found.contains(.init(relativePath: ".build/a\"b.o", directoryName: ".build")))
        #expect(found.contains(.init(relativePath: ".build/ü.o", directoryName: ".build")))
        #expect(found.count == 2)
    }

    @Test("a newline split of a quoted index line misses that scratch file")
    func newlineSplitMissesQuotedScratchFile() throws {
        let root = try makeScratchIndex()
        defer { try? FileManager.default.removeItem(at: root) }
        let plain = try ChildProcess.run(
            ["git", "-c", "core.quotePath=true", "ls-files", "--cached"],
            workingDirectory: root
        )
        #expect(plain.status == 0, "git ls-files failed: \(plain.output)")
        let lines = plain.output.split(separator: "\n", omittingEmptySubsequences: true).map(
            String.init)
        #expect(lines.contains("\".build/a\\\"b.o\""))
        #expect(lines.contains("\".build/\\303\\274.o\""))
        let missed = TrackedBuildOutput.violations(in: lines)
        #expect(missed.isEmpty, "newline split still saw a scratch folder: \(missed)")
    }

    @Test("a folder that is not a git repository fails the path listing")
    func listingFailsOutsideARepository() {
        #expect(throws: TrackedBuildOutput.ListingFailed.self) {
            try TrackedBuildOutput.listTrackedPaths(root: URL(fileURLWithPath: "/"))
        }
    }

    @Test("the repository index tracks no scratch folder")
    func repositoryTracksNoScratchFolder() throws {
        let direct = try ChildProcess.run(
            ["git", "ls-files", "-z", "--cached"],
            workingDirectory: RepositoryRoot.url
        )
        #expect(direct.status == 0, "git ls-files failed: \(direct.output)")
        let expected = direct.output.split(separator: "\0", omittingEmptySubsequences: true).map(
            String.init)
        let listed = try TrackedBuildOutput.listTrackedPaths(root: RepositoryRoot.url)
        #expect(listed == expected)
        #expect(listed.contains("Package.swift"))
        let found = TrackedBuildOutput.violations(in: listed)
        #expect(found.isEmpty, "tracked build output: \(found)")
    }

    private func randomPath(using generator: inout SeededGenerator, plant folder: String?) -> String
    {
        let count = Int.random(in: 1...5, using: &generator)
        var parts: [String] = []
        for _ in 0..<count {
            parts.append(decoys.randomElement(using: &generator)!)
        }
        if let folder {
            let index = Int.random(in: 0..<count, using: &generator)
            parts[index] = folder
        }
        return parts.joined(separator: "/")
    }

    /// A fresh index with two scratch files git would quote, and one ordinary source file.
    private func makeScratchIndex() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("scratch-index-\(UUID().uuidString)", isDirectory: true)
        let build = root.appendingPathComponent(".build", isDirectory: true)
        let sources = root.appendingPathComponent("Sources", isDirectory: true)
        try FileManager.default.createDirectory(at: build, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        try Data("q".utf8).write(to: build.appendingPathComponent("a\"b.o"))
        try Data("u".utf8).write(to: build.appendingPathComponent("ü.o"))
        try Data("k".utf8).write(to: sources.appendingPathComponent("Keep.swift"))
        let ready = try ChildProcess.run(["git", "init", "-q"], workingDirectory: root)
        try #require(ready.status == 0, "git init failed: \(ready.output)")
        let added = try ChildProcess.run(
            ["git", "add", "--", ".build/a\"b.o", ".build/ü.o", "Sources/Keep.swift"],
            workingDirectory: root
        )
        try #require(added.status == 0, "git add failed: \(added.output)")
        return root
    }

    /// The scratch folder the test expects, computed without the code under test.
    private func expectedFolder(in path: String) -> String? {
        path.split(separator: "/", omittingEmptySubsequences: false)
            .map(String.init)
            .first { scratchFolders.contains($0) }
    }
}
