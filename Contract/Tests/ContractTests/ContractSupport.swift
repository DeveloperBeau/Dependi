import CryptoKit
import DependiDomain
import DependiFileSystem
import DependiPackageGraph
import DependiProcess
import Foundation

/// Helpers that make small real packages and run the real tools.
enum ContractSupport {
    static let process = SystemProcessRunner(children: ChildProcessRegistry())
    static let disk = DiskFileSystem()

    static func temporaryFolder(_ label: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "\(label)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func run(_ executable: String, _ arguments: [String], environment: [String: String])
        throws -> ProcessOutput
    {
        try process.run(
            ProcessRequest(
                executable: executable, arguments: arguments, environment: environment,
                workingDirectory: nil,
                timeoutSeconds: 120, maximumOutputBytes: 64 * 1024 * 1024))
    }

    static var cleanEnvironment: [String: String] {
        [
            "PATH": "/usr/bin:/bin", "HOME": NSHomeDirectory(),
            "TMPDIR": FileManager.default.temporaryDirectory.path,
        ]
    }

    /// The path of the `swift` program, found the way production finds it.
    static func swiftPath() throws -> String {
        let output = try run("/usr/bin/xcrun", ["--find", "swift"], environment: cleanEnvironment)
        return String(decoding: output.standardOutput, as: UTF8.self).trimmingCharacters(
            in: .whitespacesAndNewlines)
    }

    static func iosSDKPath() -> String? {
        guard
            let output = try? run(
                "/usr/bin/xcrun", ["--sdk", "iphoneos", "--show-sdk-path"],
                environment: cleanEnvironment),
            output.exitStatus == 0
        else { return nil }
        let path = String(decoding: output.standardOutput, as: UTF8.self).trimmingCharacters(
            in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }

    /// Writes a package with the given manifest and one empty source file for each target name.
    static func makePackage(named name: String, manifest: String, targets: [String]) throws -> URL {
        let root = try temporaryFolder(name)
        try manifest.write(
            to: root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        for target in targets {
            let folder = root.appendingPathComponent("Sources/\(target)")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try "public struct \(target.replacingOccurrences(of: "-", with: "_"))Marker {}\n".write(
                to: folder.appendingPathComponent("\(target).swift"), atomically: true,
                encoding: .utf8)
        }
        return root
    }

    static func settings(scratch: URL, swift: String) -> PackageGraphSettings {
        PackageGraphSettings(
            swiftExecutable: swift, toolchainVersion: "contract",
            childEnvironment: cleanEnvironment,
            scratchDirectory: scratch.appendingPathComponent("scratch").path,
            localCacheDirectory: scratch.appendingPathComponent("local").path,
            remoteCacheDirectory: scratch.appendingPathComponent("remote").path,
            checkoutsDirectory: nil,
            processTimeoutSeconds: 120, maximumOutputBytes: 64 * 1024 * 1024,
            staleTemporaryFilesBefore: Date().addingTimeInterval(-86_400))
    }

    static func reader(scratch: URL, swift: String) -> PackageGraphReader {
        PackageGraphReader(
            settings: settings(scratch: scratch, swift: swift), process: process, files: disk,
            directories: disk,
            writer: disk)
    }

    /// A hash of every file name and content under a folder, to show that nothing changed.
    static func fingerprint(of root: URL) throws -> String {
        var lines: [String] = []
        let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.isRegularFileKey])
        while let url = enumerator?.nextObject() as? URL {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            let relative = String(url.path.dropFirst(root.path.count))
            if values.isRegularFile == true {
                let digest = SHA256.hash(data: try Data(contentsOf: url)).map {
                    String(format: "%02x", $0)
                }.joined()
                lines.append("\(relative) \(digest)")
            } else {
                lines.append("\(relative) (folder)")
            }
        }
        return lines.sorted().joined(separator: "\n")
    }
}
