import CryptoKit
import DependiDomain
import Foundation

/// Reads a package manifest by running `swift package dump-package`, and caches the result.
public struct PackageGraphReader: PackageManifestReading {
    private let settings: PackageGraphSettings
    private let process: any ProcessRunning
    private let files: any FileReading
    private let directories: any DirectoryListing
    private let writer: any FileWriting

    private static let manifestFilePattern = try! NSRegularExpression(
        pattern: #"^Package(@swift-[0-9]+(\.[0-9]+){0,2}(-[A-Za-z0-9]+)?)?\.swift$"#)
    private static let maximumManifestBytes = 4_194_304

    /// Creates a reader that uses the given settings and interfaces.
    public init(
        settings: PackageGraphSettings,
        process: any ProcessRunning,
        files: any FileReading,
        directories: any DirectoryListing,
        writer: any FileWriting
    ) {
        self.settings = settings
        self.process = process
        self.files = files
        self.directories = directories
        self.writer = writer
    }

    /// Implements `manifest` for `PackageGraphReader`.
    public func manifest(atPackagePath path: String) throws(DomainError) -> PackageManifest {
        let real = try files.realPath(of: path)
        let key = try cacheKey(for: real)
        let cachePath = cacheDirectory(for: real) + "/" + key + ".json"
        if let cached = cachedManifest(at: cachePath, key: key, packagePath: real) { return cached }
        let output = try runDumpPackage(in: real)
        let manifest = try ManifestJSONParser.parse(output, packagePath: real)
        store(output, key: key, at: cachePath)
        return manifest
    }

    // MARK: Cache

    private func isRemote(_ real: String) -> Bool {
        guard let checkouts = settings.checkoutsDirectory,
            let root = try? files.realPath(of: checkouts)
        else { return false }
        return real.hasPrefix(root + "/")
    }

    private func cacheDirectory(for real: String) -> String {
        isRemote(real) ? settings.remoteCacheDirectory : settings.localCacheDirectory
    }

    private static func hex(_ digest: SHA256.Digest) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }

    private func environmentHash() -> String {
        let lines = settings.childEnvironment.sorted { $0.key < $1.key }.map {
            "\($0.key)=\($0.value)"
        }
        return Self.hex(SHA256.hash(data: Data(lines.joined(separator: "\n").utf8)))
    }

    private func arguments(for real: String) -> [String] {
        let scratch =
            settings.scratchDirectory + "/"
            + String(Self.hex(SHA256.hash(data: Data(real.utf8))).prefix(12))
        return ["package", "--package-path", real, "--scratch-path", scratch, "dump-package"]
    }

    private func cacheKey(for real: String) throws(DomainError) -> String {
        let names = try directories.topLevelNames(in: real).filter { name in
            Self.manifestFilePattern.firstMatch(
                in: name, range: NSRange(name.startIndex..., in: name)) != nil
        }.sorted()
        if names.isEmpty { throw .fileNotFound(path: real + "/Package.swift") }
        var parts = [
            settings.toolchainVersion, environmentHash(),
            arguments(for: real).joined(separator: " "),
        ]
        for name in names {
            let realFile = try files.realPath(of: real + "/" + name)
            let data = try files.readRegularFile(at: realFile, upToBytes: Self.maximumManifestBytes)
            parts.append("\(name)\u{0}\(Self.hex(SHA256.hash(data: data)))")
        }
        return Self.hex(SHA256.hash(data: Data(parts.joined(separator: "\n").utf8)))
    }

    private func cachedManifest(at path: String, key: String, packagePath: String)
        -> PackageManifest?
    {
        guard files.exists(at: path), let real = try? files.realPath(of: path),
            let data = try? files.readRegularFile(at: real, upToBytes: settings.maximumOutputBytes),
            let entry = try? JSONDecoder().decode(ManifestCacheEntry.self, from: data),
            entry.key == key
        else { return nil }
        return try? ManifestJSONParser.parse(Data(entry.dump.utf8), packagePath: packagePath)
    }

    private func store(_ output: Data, key: String, at path: String) {
        guard let text = String(data: output, encoding: .utf8),
            let data = try? JSONEncoder().encode(ManifestCacheEntry(key: key, dump: text))
        else { return }
        let directory = String(path[..<(path.lastIndex(of: "/") ?? path.endIndex)])
        sweepStaleTemporaryFiles(in: directory)
        // A cache that cannot be written only costs time on the next run, so it never fails a read.
        try? writer.createDirectory(at: directory)
        try? writer.write(data, toPath: path)
    }

    /// Removes the `.tmp-<UUID>` files that an interrupted cache write left behind.
    /// A file is removed only if it is old, so a write that is running now is never touched.
    private func sweepStaleTemporaryFiles(in directory: String) {
        guard files.exists(at: directory), let names = try? directories.topLevelNames(in: directory)
        else { return }
        for name in names where Self.isTemporaryCacheFile(name) {
            let path = directory + "/" + name
            guard let changed = files.modificationDate(of: path),
                changed < settings.staleTemporaryFilesBefore
            else { continue }
            try? writer.removeItem(at: path)
        }
    }

    private static func isTemporaryCacheFile(_ name: String) -> Bool {
        guard let range = name.range(of: ".json.tmp-", options: .backwards),
            range.lowerBound != name.startIndex
        else { return false }
        return UUID(uuidString: String(name[range.upperBound...])) != nil
    }

    // MARK: Process

    /// Turns child output into text for the build log. Control characters, such as escape
    /// sequences, become spaces. Newline and tab stay.
    static func printable(_ bytes: Data) -> String {
        let text = String(decoding: bytes, as: UTF8.self)
        let cleaned = text.unicodeScalars.map { scalar -> Character in
            let value = scalar.value
            let isControl = value < 0x20 || value == 0x7F || (0x80...0x9F).contains(value)
            return isControl && scalar != "\n" && scalar != "\t" ? " " : Character(scalar)
        }
        return String(cleaned)
    }

    private func runDumpPackage(in real: String) throws(DomainError) -> Data {
        let request = ProcessRequest(
            executable: settings.swiftExecutable, arguments: arguments(for: real),
            environment: settings.childEnvironment, workingDirectory: nil,
            timeoutSeconds: settings.processTimeoutSeconds,
            maximumOutputBytes: settings.maximumOutputBytes)
        let result = try process.run(request)
        guard result.exitStatus == 0 else {
            let message = Self.printable(result.standardError.prefix(300))
            throw .processFailed(
                command: "swift package dump-package",
                reason: "exit status \(result.exitStatus) for the package at \(real): \(message)")
        }
        return result.standardOutput
    }
}
