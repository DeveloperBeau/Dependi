import DependiDomain
import DependiEntities
import DependiPackageGraph
import Foundation

/// Reads manifests, and starts the toolchain lookup only when the first manifest is needed.
/// A skipped build therefore starts no process at all.
final class LazyManifestReader: PackageManifestReading, @unchecked Sendable {
    private let environment: [String: String]
    private let process: any ProcessRunning
    private let files: any FileReading
    private let directories: any DirectoryListing
    private let writer: any FileWriting
    private let lock = NSLock()
    private var reader: PackageGraphReader?

    init(
        environment: [String: String], process: any ProcessRunning, files: any FileReading,
        directories: any DirectoryListing, writer: any FileWriting
    ) {
        self.environment = environment
        self.process = process
        self.files = files
        self.directories = directories
        self.writer = writer
    }

    func manifest(atPackagePath path: String) throws(DomainError) -> PackageManifest {
        try current().manifest(atPackagePath: path)
    }

    private func current() throws(DomainError) -> PackageGraphReader {
        lock.lock()
        defer { lock.unlock() }
        if let reader { return reader }
        let created = PackageGraphReader(
            settings: try Self.settings(environment: environment, process: process),
            process: process,
            files: files, directories: directories, writer: writer)
        reader = created
        return created
    }

    private static func cleanEnvironment(_ environment: [String: String]) -> [String: String] {
        var result = ["PATH": "/usr/bin:/bin", "TMPDIR": environment["TMPDIR"] ?? "/tmp"]
        if let home = environment["HOME"] { result["HOME"] = home }
        if let developer = environment["DEVELOPER_DIR"] { result["DEVELOPER_DIR"] = developer }
        return result
    }

    private static func settings(
        environment: [String: String], process: any ProcessRunning
    ) throws(DomainError) -> PackageGraphSettings {
        let child = cleanEnvironment(environment)
        func run(_ executable: String, _ arguments: [String]) throws(DomainError) -> String {
            let output = try process.run(
                ProcessRequest(
                    executable: executable, arguments: arguments, environment: child,
                    workingDirectory: nil,
                    timeoutSeconds: 60, maximumOutputBytes: 1_048_576))
            guard output.exitStatus == 0 else {
                throw .processFailed(
                    command: executable, reason: "exit status \(output.exitStatus)")
            }
            return String(decoding: output.standardOutput, as: UTF8.self).trimmingCharacters(
                in: .whitespacesAndNewlines)
        }
        let swift = try run("/usr/bin/xcrun", ["--find", "swift"])
        guard swift.hasPrefix("/") else {
            throw .processFailed(
                command: "/usr/bin/xcrun", reason: "it did not print the path of swift")
        }
        let version: String
        if let build = environment["XCODE_PRODUCT_BUILD_VERSION"], !build.isEmpty {
            version = build
        } else {
            version =
                try run(swift, ["--version"]).split(separator: "\n").first.map(String.init)
                ?? "unknown"
        }
        let buildBase = environment["BUILD_DIR"] ?? child["TMPDIR"] ?? "/tmp"
        let home = environment["HOME"] ?? child["TMPDIR"] ?? "/tmp"
        let checkouts =
            (try? SourcePackagesLocator().locate(
                buildDirectory: environment["BUILD_DIR"], configuredPath: nil))
            .map { $0 + "/checkouts" }
        return PackageGraphSettings(
            swiftExecutable: swift, toolchainVersion: version, childEnvironment: child,
            scratchDirectory: buildBase + "/dependi/scratch",
            localCacheDirectory: buildBase + "/dependi/manifests",
            remoteCacheDirectory: home + "/Library/Caches/dependi/manifests",
            checkoutsDirectory: checkouts,
            processTimeoutSeconds: ToolConfiguration.defaultProcessTimeoutSeconds,
            maximumOutputBytes: 64 * 1024 * 1024)
    }
}
