import DependiPackageGraph
import DependiDomain
import DependiTestSupport
import Foundation
import TestHelpers

/// Shared setup for the package graph reader tests.
enum GraphTestSupport {
    /// The moment before which a temporary cache file counts as stale.
    static let cutoff = Date(timeIntervalSince1970: 1_000_000)
    static let packagePath = "/checkouts/kit"

    static func fixture(_ name: String) throws -> Data {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(name).json")
        return try Data(contentsOf: url)
    }

    static func settings(
        toolchain: String = "swift-6.4.2",
        environment: [String: String] = ["HOME": "/h", "PATH": "/usr/bin:/bin"],
        checkouts: String? = "/checkouts"
    ) -> PackageGraphSettings {
        PackageGraphSettings(
            swiftExecutable: "/toolchain/usr/bin/swift", toolchainVersion: toolchain,
            childEnvironment: environment,
            scratchDirectory: "/build/dependi/scratch",
            localCacheDirectory: "/build/dependi/manifests",
            remoteCacheDirectory: "/cache/dependi/manifests", checkoutsDirectory: checkouts,
            processTimeoutSeconds: 45, maximumOutputBytes: 64 * 1024 * 1024,
            staleTemporaryFilesBefore: cutoff)
    }

    static func files(
        packagePath: String = packagePath, extra: [String: String] = [:]
    ) throws -> InMemoryFileSystem {
        let files = InMemoryFileSystem()
        try files.addDirectory(at: packagePath)
        try files.addDirectory(at: "/checkouts")
        try files.addDirectory(at: "/build/dependi")
        try files.addDirectory(at: "/cache")
        try files.addFile(at: packagePath + "/Package.swift", contents: Data("// manifest".utf8))
        for (name, text) in extra {
            try files.addFile(at: packagePath + "/" + name, contents: Data(text.utf8))
        }
        return files
    }

    static func success(_ data: Data) -> Result<ProcessOutput, DomainError> {
        .success(ProcessOutput(exitStatus: 0, standardOutput: data, standardError: Data()))
    }

    static func reader(
        files: InMemoryFileSystem, runner: FakeProcessRunner,
        settings: PackageGraphSettings = settings()
    ) -> PackageGraphReader {
        PackageGraphReader(
            settings: settings, process: runner, files: files, directories: files, writer: files)
    }
}
