import Foundation

/// Reads files without following a link in the last path component.
public protocol FileReading: Sendable {
    /// Resolves every symbolic link in a path and returns the absolute path.
    func realPath(of path: String) throws(DomainError) -> String

    /// Reads a regular file at an already resolved path.
    ///
    /// It refuses a link, a folder, a pipe and a device. It returns at most `limit + 1` bytes,
    /// so a caller can tell that a file is longer than `limit`.
    func readRegularFile(at realPath: String, upToBytes limit: Int) throws(DomainError) -> Data

    /// Returns whether anything exists at the path, without following a final link.
    func exists(at path: String) -> Bool

    /// Returns when the item at the path was last changed, without following a final link.
    /// It returns `nil` if the item does not exist or its age is not known.
    func modificationDate(of path: String) -> Date?
}

extension FileReading {
    /// A reader that cannot tell the age of a file reports that it does not know.
    public func modificationDate(of path: String) -> Date? { nil }
}
