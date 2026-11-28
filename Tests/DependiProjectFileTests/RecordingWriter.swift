import DependiDomain
import DependiTestSupport
import Foundation

/// Passes every change to an in-memory file system and records it in order.
///
/// A change whose record starts with `failingPrefix` fails with `fileUnwritable`. A write whose
/// record starts with `alteringPrefix` stores one more byte than it was given.
final class RecordingWriter: FileWriting, @unchecked Sendable {
    private let inner: InMemoryFileSystem
    private let failingPrefix: String?
    private let alteringPrefix: String?
    private let box = LockedBox<[String]>([])

    init(
        _ inner: InMemoryFileSystem, failingPrefix: String? = nil, alteringPrefix: String? = nil
    ) {
        self.inner = inner
        self.failingPrefix = failingPrefix
        self.alteringPrefix = alteringPrefix
    }

    /// Every change in the order it was attempted, such as `write /a/b` or `move /a to /b`.
    var records: [String] { box.withValue { $0 } }

    private func record(_ text: String, path: String) throws(DomainError) {
        box.withValue { $0.append(text) }
        if let failingPrefix, text.hasPrefix(failingPrefix) {
            throw .fileUnwritable(path: path, reason: "stopped by the test")
        }
    }

    func write(_ data: Data, toPath path: String) throws(DomainError) {
        let text = "write \(path)"
        try record(text, path: path)
        let altered = alteringPrefix.map { text.hasPrefix($0) } ?? false
        try inner.write(altered ? data + Data([0x20]) : data, toPath: path)
    }

    func createDirectory(at path: String) throws(DomainError) {
        try record("mkdir \(path)", path: path)
        try inner.createDirectory(at: path)
    }

    func removeItem(at path: String) throws(DomainError) {
        try record("remove \(path)", path: path)
        try inner.removeItem(at: path)
    }

    func moveItem(at source: String, to destination: String) throws(DomainError) {
        try record("move \(source) to \(destination)", path: destination)
        try inner.moveItem(at: source, to: destination)
    }
}
