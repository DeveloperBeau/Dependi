import Foundation

/// Writes, moves and removes files and folders.
public protocol FileWriting: Sendable {
    /// Writes a file. The folder that holds it must exist.
    func write(_ data: Data, toPath path: String) throws(DomainError)

    /// Creates a folder and any missing parent folders.
    func createDirectory(at path: String) throws(DomainError)

    /// Removes a file or a folder with everything in it.
    func removeItem(at path: String) throws(DomainError)

    /// Moves an item to a new path and replaces what is there.
    func moveItem(at source: String, to destination: String) throws(DomainError)
}
