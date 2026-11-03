import DependiDomain
import Foundation

extension DiskFileSystem {
    /// Sets the mode of the file to `rwxr-xr-x`. A link is followed to its target.
    public func makeExecutable(at path: String) throws(DomainError) {
        if chmod(path, 0o755) != 0 {
            let code = errno
            if code == ENOENT { throw .fileNotFound(path: path) }
            throw .fileUnwritable(
                path: path, reason: "chmod failed: \(String(cString: strerror(code)))")
        }
    }
}
