import Foundation

/// Builds a file tree for a behavior suite. One conformer exists for the double and one for disk.
public protocol FileTreeArranging {
    /// Creates a regular file. The folder that holds it already exists.
    func addFile(at path: String, contents: Data) throws

    /// Creates a folder and any missing parent folders.
    func addDirectory(at path: String) throws

    /// Creates a symbolic link at `path` that points to `target`.
    func addSymlink(at path: String, pointingTo target: String) throws

    /// Creates a named pipe.
    func addNamedPipe(at path: String) throws
}
