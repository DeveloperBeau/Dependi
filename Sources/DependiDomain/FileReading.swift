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
}
