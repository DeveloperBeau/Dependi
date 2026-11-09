import DependiDomain
import DependiEntities
import DependiTestSupport
import Foundation

@testable import DependiSettingsBundle

let bundle = "/products/App.app/Settings.bundle"

func makeAck(
    _ name: String, location: String? = nil, docs: [(String, String)] = [("LICENSE", "text")]
) -> Acknowledgement {
    Acknowledgement(
        displayName: name,
        identity: PackageIdentity(name.lowercased()),
        normalizedLocation: location ?? "github.com/o/\(name.lowercased())",
        documents: docs.map { try! LicenseDocument(fileName: $0.0, text: $0.1) }
    )
}

func slugOf(_ ack: Acknowledgement) -> String {
    OutputNameSlugger().slug(
        identity: ack.identity, normalizedLocation: ack.normalizedLocation)
}

func makeWriter(
    _ fs: InMemoryFileSystem, reader: (any FileReading)? = nil, writes: (any FileWriting)? = nil
) -> SettingsBundleWriter {
    SettingsBundleWriter(
        files: reader ?? fs, directories: fs, writer: writes ?? fs, slugger: OutputNameSlugger())
}

func freshFileSystem() throws -> InMemoryFileSystem {
    let fs = InMemoryFileSystem()
    try fs.createDirectory(at: bundle)
    return fs
}

func readBytes(_ fs: InMemoryFileSystem, _ path: String) throws -> Data {
    try fs.readRegularFile(at: path, upToBytes: 10_000_000)
}

func readPlist(_ fs: InMemoryFileSystem, _ path: String) throws -> NSDictionary {
    let data = try readBytes(fs, path)
    return try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        as! NSDictionary
}

/// Every path in the tree, found with the listing interface only.
func allPaths(_ fs: InMemoryFileSystem, under root: String = "/") throws -> [String] {
    var result: [String] = []
    for name in try fs.topLevelNames(in: root) {
        let path = root == "/" ? "/" + name : root + "/" + name
        result.append(path)
        if (try? fs.topLevelNames(in: path)) != nil { result += try allPaths(fs, under: path) }
    }
    return result.sorted()
}

/// Counts writes and removals and passes them on.
final class CountingWriter: FileWriting, @unchecked Sendable {
    let inner: InMemoryFileSystem
    private let box = LockedBox<[String]>([])
    init(_ inner: InMemoryFileSystem) { self.inner = inner }
    var writtenPaths: [String] { box.withValue { $0 } }
    var removedPaths: [String] { box.withValue { $0 }.filter { $0.hasPrefix("rm ") } }
    func write(_ data: Data, toPath path: String) throws(DomainError) {
        box.withValue { $0.append(path) }
        try inner.write(data, toPath: path)
    }
    func createDirectory(at path: String) throws(DomainError) {
        try inner.createDirectory(at: path)
    }
    func removeItem(at path: String) throws(DomainError) {
        box.withValue { $0.append("rm " + path) }
        try inner.removeItem(at: path)
    }
    func moveItem(at source: String, to destination: String) throws(DomainError) {
        try inner.moveItem(at: source, to: destination)
    }
}

/// Adds a letter to the first plist string it reads, so the file stays a valid plist.
struct AlteringReader: FileReading {
    let inner: InMemoryFileSystem
    func realPath(of path: String) throws(DomainError) -> String { try inner.realPath(of: path) }
    func readRegularFile(at realPath: String, upToBytes limit: Int) throws(DomainError) -> Data {
        let data = try inner.readRegularFile(at: realPath, upToBytes: limit)
        guard let text = String(data: data, encoding: .utf8), realPath.hasSuffix(".plist") else {
            return data
        }
        return Data(text.replacingOccurrences(of: "<string>", with: "<string>X").utf8)
    }
    func exists(at path: String) -> Bool { inner.exists(at: path) }
}

/// Passes the first `allowed` changes to the file system and fails every later one.
final class FailingAfterWriter: FileWriting, @unchecked Sendable {
    let inner: InMemoryFileSystem
    private let allowed: Int
    private let box = LockedBox<Int>(0)
    init(_ inner: InMemoryFileSystem, allowing allowed: Int) {
        self.inner = inner
        self.allowed = allowed
    }
    /// How many changes were attempted, failed ones included.
    var attempts: Int { box.withValue { $0 } }
    private func gate(_ path: String) throws(DomainError) {
        let count = box.withValue { value -> Int in
            value += 1
            return value
        }
        if count > allowed { throw .fileUnwritable(path: path, reason: "stopped") }
    }
    func write(_ data: Data, toPath path: String) throws(DomainError) {
        try gate(path)
        try inner.write(data, toPath: path)
    }
    func createDirectory(at path: String) throws(DomainError) {
        try gate(path)
        try inner.createDirectory(at: path)
    }
    func removeItem(at path: String) throws(DomainError) {
        try gate(path)
        try inner.removeItem(at: path)
    }
    func moveItem(at source: String, to destination: String) throws(DomainError) {
        try gate(source)
        try inner.moveItem(at: source, to: destination)
    }
}
