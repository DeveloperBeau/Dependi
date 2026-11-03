import DependiTestSupport
import Foundation

/// Builds file trees on the real disk for the shared behavior suite and the real-tree tests.
struct DiskTreeArranger: FileTreeArranging {
    func addFile(at path: String, contents: Data) throws {
        let parent = URL(fileURLWithPath: path).deletingLastPathComponent().path
        try FileManager.default.createDirectory(atPath: parent, withIntermediateDirectories: true)
        try contents.write(to: URL(fileURLWithPath: path))
    }

    func addDirectory(at path: String) throws {
        try FileManager.default.createDirectory(
            atPath: path, withIntermediateDirectories: true)
    }

    func addSymlink(at path: String, pointingTo target: String) throws {
        if symlink(target, path) != 0 { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }

    func addNamedPipe(at path: String) throws {
        if mkfifo(path, 0o644) != 0 { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }
}
