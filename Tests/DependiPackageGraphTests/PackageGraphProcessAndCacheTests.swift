@testable import DependiPackageGraph
import DependiDomain
import DependiTestSupport
import Foundation
import Testing

@Suite("Package graph process and cache", .timeLimit(.minutes(5)))
struct PackageGraphProcessAndCacheTests {
    private let log = try! GraphTestSupport.fixture("swift-log")

    private func reader(
        _ files: InMemoryFileSystem, _ runner: FakeProcessRunner,
        _ settings: PackageGraphSettings = GraphTestSupport.settings()
    ) -> PackageGraphReader {
        GraphTestSupport.reader(files: files, runner: runner, settings: settings)
    }

    private func runs(_ count: Int) -> FakeProcessRunner {
        FakeProcessRunner(results: Array(repeating: GraphTestSupport.success(log), count: count))
    }

    // MARK: The request

    @Test("the request names the swift program, the exact arguments and the clean environment")
    func requestShape() throws {
        let files = try GraphTestSupport.files()
        let runner = runs(1)
        _ = try reader(files, runner).manifest(atPackagePath: GraphTestSupport.packagePath)
        let request = try #require(runner.requests.first)
        #expect(request.executable == "/toolchain/usr/bin/swift")
        #expect(
            request.arguments == [
                "package", "--package-path", "/checkouts/kit", "--scratch-path",
                "/build/dependi/scratch/53f9764981e0", "dump-package",
            ])
        #expect(request.environment == ["HOME": "/h", "PATH": "/usr/bin:/bin"])
        #expect(request.environment["SDKROOT"] == nil)
        #expect(request.timeoutSeconds == 45)
        #expect(request.maximumOutputBytes == 64 * 1024 * 1024)
        #expect(!request.arguments.contains("--disable-sandbox"))
    }

    @Test("each package gets its own scratch folder and none is inside a package")
    func scratchFoldersAreUniqueAndOutside() throws {
        let files = try GraphTestSupport.files()
        try files.addDirectory(at: "/proj/Packages/core")
        try files.addFile(at: "/proj/Packages/core/Package.swift", contents: Data("// m".utf8))
        let runner = runs(2)
        let graph = reader(files, runner)
        _ = try graph.manifest(atPackagePath: "/checkouts/kit")
        _ = try graph.manifest(atPackagePath: "/proj/Packages/core")
        let scratch = runner.requests.map { $0.arguments[4] }
        #expect(
            scratch == [
                "/build/dependi/scratch/53f9764981e0", "/build/dependi/scratch/52b8a98fa7f6",
            ])
        #expect(
            !scratch[0].hasPrefix("/checkouts/kit") && !scratch[1].hasPrefix("/proj/Packages/core"))
    }

    // MARK: Failures

    @Test("a non-zero exit names the command, the status, the package and the first error text")
    func nonZeroExit() throws {
        let files = try GraphTestSupport.files()
        let failure = ProcessOutput(
            exitStatus: 1, standardOutput: Data(), standardError: Data("error: bad manifest".utf8))
        let runner = FakeProcessRunner(results: [.success(failure)])
        #expect(
            throws: DomainError.processFailed(
                command: "swift package dump-package",
                reason: "exit status 1 for the package at /checkouts/kit: error: bad manifest")
        ) { try reader(files, runner).manifest(atPackagePath: GraphTestSupport.packagePath) }
    }

    @Test("a failure from the process runner is passed through")
    func runnerFailurePassedThrough() throws {
        let files = try GraphTestSupport.files()
        let error = DomainError.processFailed(
            command: "/toolchain/usr/bin/swift", reason: "timed out after 45 seconds")
        let runner = FakeProcessRunner(results: [.failure(error)])
        #expect(throws: error) {
            try reader(files, runner).manifest(atPackagePath: GraphTestSupport.packagePath)
        }
    }

    @Test("a folder without any manifest file is not found")
    func noManifestFile() throws {
        let files = try GraphTestSupport.files()
        try files.removeItem(at: "/checkouts/kit/Package.swift")
        try files.addFile(at: "/checkouts/kit/Package.swift.bak", contents: Data("x".utf8))
        try files.addFile(at: "/checkouts/kit/Package.swift~", contents: Data("x".utf8))
        let runner = runs(0)
        #expect(throws: DomainError.fileNotFound(path: "/checkouts/kit/Package.swift")) {
            try reader(files, runner).manifest(atPackagePath: GraphTestSupport.packagePath)
        }
        #expect(runner.requests.isEmpty)
    }

    // MARK: Cache hits and tiers

    @Test("a second read of an unchanged package does not start a process")
    func secondReadIsServedFromTheCache() throws {
        let files = try GraphTestSupport.files()
        let runner = runs(1)
        let graph = reader(files, runner)
        let first = try graph.manifest(atPackagePath: GraphTestSupport.packagePath)
        let second = try graph.manifest(atPackagePath: GraphTestSupport.packagePath)
        #expect(first == second)
        #expect(runner.requests.count == 1)
    }

    @Test(
        "a package in the checkouts folder uses the remote cache and any other package uses the local cache"
    )
    func cacheTiers() throws {
        let files = try GraphTestSupport.files()
        try files.addDirectory(at: "/proj/Packages/core")
        try files.addFile(at: "/proj/Packages/core/Package.swift", contents: Data("// m".utf8))
        let runner = runs(2)
        let graph = reader(files, runner)
        _ = try graph.manifest(atPackagePath: "/checkouts/kit")
        _ = try graph.manifest(atPackagePath: "/proj/Packages/core")
        #expect(try files.topLevelNames(in: "/cache/dependi/manifests").count == 1)
        #expect(try files.topLevelNames(in: "/build/dependi/manifests").count == 1)
    }

    @Test("a read-only cache folder does not fail the read")
    func readOnlyCacheDoesNotFail() throws {
        let files = try GraphTestSupport.files()
        files.markReadOnly("/cache")
        files.markReadOnly("/build")
        let runner = runs(2)
        let graph = reader(files, runner)
        _ = try graph.manifest(atPackagePath: GraphTestSupport.packagePath)
        _ = try graph.manifest(atPackagePath: GraphTestSupport.packagePath)
        #expect(runner.requests.count == 2)
    }

    // MARK: Child output in the build log

    @Test("control characters and escape sequences in child errors never reach the message")
    func childErrorIsPrintable() throws {
        let files = try GraphTestSupport.files()
        let text = "\u{1B}[31merror\u{1B}[0m: bad\u{07}\r\nline two\ttab\u{7F}\u{85}end\0"
        let failure = ProcessOutput(
            exitStatus: 1, standardOutput: Data(), standardError: Data(text.utf8))
        let runner = FakeProcessRunner(results: [.success(failure)])
        #expect(
            throws: DomainError.processFailed(
                command: "swift package dump-package",
                reason:
                    "exit status 1 for the package at /checkouts/kit:  [31merror [0m: bad  \nline two\ttab  end "
            )
        ) { try reader(files, runner).manifest(atPackagePath: GraphTestSupport.packagePath) }
    }

    @Test("plain text, newlines, tabs and non-ASCII letters stay as they are")
    func printableTextIsKept() {
        let text = "error: caf\u{E9} \u{4E2D}\n\tat line 3"
        #expect(PackageGraphReader.printable(Data(text.utf8)) == text)
    }

    @Test("bytes that are not UTF-8 become replacement characters and no control byte survives")
    func invalidBytesAreReplaced() {
        let result = PackageGraphReader.printable(Data([0x41, 0xFF, 0x1B, 0x42]))
        #expect(result == "A\u{FFFD} B")
    }

    // MARK: Leftovers in the cache folder

    private static let uuid = "0E4C1B6A-5D3F-4B7E-9A21-6C8D2F1E3A45"
    private static let cache = "/cache/dependi/manifests"

    @Test("an old temporary file in the cache folder is removed when the cache is written")
    func staleTemporaryFilesAreSwept() throws {
        let files = try GraphTestSupport.files()
        try files.addDirectory(at: "/checkouts/other")
        try files.addFile(at: "/checkouts/other/Package.swift", contents: Data("// o".utf8))
        let graph = reader(files, runs(2))
        _ = try graph.manifest(atPackagePath: "/checkouts/kit")
        let old = "\(Self.cache)/abc.json.tmp-\(Self.uuid)"
        let fresh = "\(Self.cache)/def.json.tmp-\(Self.uuid)"
        let unknownAge = "\(Self.cache)/ghi.json.tmp-\(Self.uuid)"
        let foreignOld = "\(Self.cache)/notes.txt"
        let notUUID = "\(Self.cache)/jkl.json.tmp-123"
        for path in [old, fresh, unknownAge, foreignOld, notUUID] {
            try files.addFile(at: path, contents: Data("x".utf8))
        }
        let before = GraphTestSupport.cutoff
        files.setModificationDate(before.addingTimeInterval(-1), at: old)
        files.setModificationDate(before.addingTimeInterval(1), at: fresh)
        files.setModificationDate(before.addingTimeInterval(-1), at: foreignOld)
        files.setModificationDate(before.addingTimeInterval(-1), at: notUUID)
        _ = try graph.manifest(atPackagePath: "/checkouts/other")
        #expect(!files.exists(at: old))
        #expect(files.exists(at: fresh))
        #expect(files.exists(at: unknownAge))
        #expect(files.exists(at: foreignOld))
        #expect(files.exists(at: notUUID))
    }

    @Test("a cache hit does not touch the cache folder")
    func cacheHitSweepsNothing() throws {
        let files = try GraphTestSupport.files()
        let graph = reader(files, runs(1))
        _ = try graph.manifest(atPackagePath: "/checkouts/kit")
        let old = "\(Self.cache)/abc.json.tmp-\(Self.uuid)"
        try files.addFile(at: old, contents: Data("x".utf8))
        files.setModificationDate(GraphTestSupport.cutoff.addingTimeInterval(-1), at: old)
        _ = try graph.manifest(atPackagePath: "/checkouts/kit")
        #expect(files.exists(at: old))
    }

    @Test("a cache that cannot be swept or written still returns the manifest")
    func unwritableCacheStillReads() throws {
        let files = try GraphTestSupport.files()
        try files.addDirectory(at: Self.cache)
        let old = "\(Self.cache)/abc.json.tmp-\(Self.uuid)"
        try files.addFile(at: old, contents: Data("x".utf8))
        files.setModificationDate(GraphTestSupport.cutoff.addingTimeInterval(-1), at: old)
        files.markReadOnly("/cache")
        let manifest = try reader(files, runs(1)).manifest(atPackagePath: "/checkouts/kit")
        #expect(!manifest.products.isEmpty)
        #expect(files.exists(at: old))
    }

    // MARK: Cache invalidation

    @Test("a changed Package.swift is read again")
    func changedManifestInvalidates() throws {
        let files = try GraphTestSupport.files()
        let runner = runs(2)
        let graph = reader(files, runner)
        _ = try graph.manifest(atPackagePath: GraphTestSupport.packagePath)
        try files.write(Data("// changed".utf8), toPath: "/checkouts/kit/Package.swift")
        _ = try graph.manifest(atPackagePath: GraphTestSupport.packagePath)
        #expect(runner.requests.count == 2)
    }

    @Test("a changed versioned manifest is read again")
    func versionedManifestInvalidates() throws {
        let files = try GraphTestSupport.files(extra: ["Package@swift-6.0.swift": "// v1"])
        let runner = runs(3)
        let graph = reader(files, runner)
        _ = try graph.manifest(atPackagePath: GraphTestSupport.packagePath)
        try files.write(Data("// v2".utf8), toPath: "/checkouts/kit/Package@swift-6.0.swift")
        _ = try graph.manifest(atPackagePath: GraphTestSupport.packagePath)
        try files.addFile(
            at: "/checkouts/kit/Package@swift-5.9.swift", contents: Data("// new".utf8))
        _ = try graph.manifest(atPackagePath: GraphTestSupport.packagePath)
        #expect(runner.requests.count == 3)
    }

    @Test("a different toolchain or a different child environment is read again")
    func toolchainAndEnvironmentInvalidate() throws {
        let files = try GraphTestSupport.files()
        let runner = runs(3)
        _ = try reader(files, runner).manifest(atPackagePath: GraphTestSupport.packagePath)
        _ = try reader(files, runner, GraphTestSupport.settings(toolchain: "swift-6.5"))
            .manifest(atPackagePath: GraphTestSupport.packagePath)
        _ = try reader(files, runner, GraphTestSupport.settings(environment: ["HOME": "/other"]))
            .manifest(atPackagePath: GraphTestSupport.packagePath)
        #expect(runner.requests.count == 3)
    }

    @Test("an unchanged package is served from the cache by a new reader with the same settings")
    func newReaderSharesTheCache() throws {
        let files = try GraphTestSupport.files()
        let runner = runs(1)
        _ = try reader(files, runner).manifest(atPackagePath: GraphTestSupport.packagePath)
        _ = try reader(files, runner).manifest(atPackagePath: GraphTestSupport.packagePath)
        #expect(runner.requests.count == 1)
    }

    @Test("files that only look like manifests do not change the key")
    func lookalikeFilesDoNotInvalidate() throws {
        let files = try GraphTestSupport.files()
        let runner = runs(1)
        let graph = reader(files, runner)
        _ = try graph.manifest(atPackagePath: GraphTestSupport.packagePath)
        try files.addFile(at: "/checkouts/kit/Package.swift.bak", contents: Data("x".utf8))
        try files.addFile(at: "/checkouts/kit/Package.resolved", contents: Data("x".utf8))
        _ = try graph.manifest(atPackagePath: GraphTestSupport.packagePath)
        #expect(runner.requests.count == 1)
    }

    // MARK: Damaged cache entries are misses

    private func onlyCacheFile(_ files: InMemoryFileSystem) throws -> String {
        let names = try files.topLevelNames(in: "/cache/dependi/manifests")
        return "/cache/dependi/manifests/" + (try #require(names.first))
    }

    @Test(
        "a damaged cache entry is a miss that is recomputed, never an empty graph",
        arguments: [
            "", "not json", "{}", "[]", "{\"key\":\"wrong\",\"dump\":\"{}\"}",
            "{\"key\":1,\"dump\":2}",
        ])
    func damagedEntryIsAMiss(content: String) throws {
        let files = try GraphTestSupport.files()
        let runner = runs(2)
        let graph = reader(files, runner)
        let first = try graph.manifest(atPackagePath: GraphTestSupport.packagePath)
        try files.write(Data(content.utf8), toPath: try onlyCacheFile(files))
        let again = try graph.manifest(atPackagePath: GraphTestSupport.packagePath)
        #expect(again == first)
        #expect(!again.products.isEmpty)
        #expect(runner.requests.count == 2)
    }

    @Test("an entry with the right key but a damaged dump is a miss")
    func rightKeyDamagedDump() throws {
        let files = try GraphTestSupport.files()
        let runner = runs(2)
        let graph = reader(files, runner)
        _ = try graph.manifest(atPackagePath: GraphTestSupport.packagePath)
        let path = try onlyCacheFile(files)
        let name = String(path.split(separator: "/").last!.dropLast(5))
        try files.write(Data("{\"key\":\"\(name)\",\"dump\":\"{broken\"}".utf8), toPath: path)
        let again = try graph.manifest(atPackagePath: GraphTestSupport.packagePath)
        #expect(!again.products.isEmpty)
        #expect(runner.requests.count == 2)
    }

    @Test("an entry with a valid dump but the wrong key is a miss")
    func wrongKeyValidDumpIsAMiss() throws {
        let files = try GraphTestSupport.files()
        let runner = runs(2)
        let graph = reader(files, runner)
        _ = try graph.manifest(atPackagePath: GraphTestSupport.packagePath)
        let path = try onlyCacheFile(files)
        let real = try files.realPath(of: path)
        let stored = try files.readRegularFile(at: real, upToBytes: 10_000_000)
        var entry = try #require(
            try JSONSerialization.jsonObject(with: stored) as? [String: String])
        entry["key"] = "some-other-key"
        try files.write(try JSONSerialization.data(withJSONObject: entry), toPath: path)
        _ = try graph.manifest(atPackagePath: GraphTestSupport.packagePath)
        #expect(runner.requests.count == 2)
    }
}
