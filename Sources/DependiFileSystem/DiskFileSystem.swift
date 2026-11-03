import DependiDomain
import Darwin
import Foundation

/// The real file system. It holds no configuration. Every error keeps the text of the system error.
public struct DiskFileSystem: FileReading, FileWriting, DirectoryListing {
    /// Creates a file system that works on the real disk.
    public init() {}

    // MARK: FileReading

    /// Resolves every link with `realpath` and returns the absolute path.
    public func realPath(of path: String) throws(DomainError) -> String {
        guard let resolved = realpath(path, nil) else {
            let code = errno
            switch code {
            case ENOENT, ENOTDIR: throw .fileNotFound(path: path)
            case ELOOP: throw .symlinkLoop(path: path)
            default: throw .fileUnreadable(path: path, reason: Self.reason("realpath", code))
            }
        }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    /// Reads a regular file and returns at most `limit + 1` bytes.
    public func readRegularFile(at realPath: String, upToBytes limit: Int) throws(DomainError)
        -> Data
    {
        let descriptor = open(realPath, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        if descriptor < 0 {
            let code = errno
            switch code {
            case ENOENT: throw .fileNotFound(path: realPath)
            case ELOOP, ENOTDIR: throw .notRegularFile(path: realPath)
            default: throw .fileUnreadable(path: realPath, reason: Self.reason("open", code))
            }
        }
        defer { close(descriptor) }
        var info = stat()
        if fstat(descriptor, &info) != 0 {
            throw .fileUnreadable(path: realPath, reason: Self.reason("fstat", errno))
        }
        guard (info.st_mode & S_IFMT) == S_IFREG else { throw .notRegularFile(path: realPath) }
        let wanted = limit < Int.max ? max(limit, 0) + 1 : limit
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 65_536)
        while result.count < wanted {
            let count = min(buffer.count, wanted - result.count)
            let got = read(descriptor, &buffer, count)
            if got < 0 {
                let code = errno
                if code == EINTR { continue }
                throw .fileUnreadable(path: realPath, reason: Self.reason("read", code))
            }
            if got == 0 { break }
            result.append(contentsOf: buffer[0..<got])
        }
        return result
    }

    /// Returns whether `lstat` finds the path. A dangling link exists.
    public func exists(at path: String) -> Bool {
        var info = stat()
        return lstat(path, &info) == 0
    }

    // MARK: DirectoryListing

    /// Returns the sorted names directly inside a folder.
    public func topLevelNames(in directory: String) throws(DomainError) -> [String] {
        guard let handle = opendir(directory) else {
            let code = errno
            if code == ENOENT { throw .fileNotFound(path: directory) }
            throw .fileUnreadable(path: directory, reason: Self.reason("opendir", code))
        }
        defer { closedir(handle) }
        var names: [String] = []
        while true {
            errno = 0
            guard let entry = readdir(handle) else {
                let code = errno
                if code != 0 {
                    throw .fileUnreadable(path: directory, reason: Self.reason("readdir", code))
                }
                break
            }
            let name = withUnsafePointer(to: &entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(entry.pointee.d_namlen) + 1) {
                    String(cString: $0)
                }
            }
            if name != "." && name != ".." { names.append(name) }
        }
        return names.sorted()
    }

    // MARK: FileWriting

    /// Writes to a temporary sibling file and renames it over the target.
    public func write(_ data: Data, toPath path: String) throws(DomainError) {
        let temporary = path + ".tmp-" + UUID().uuidString
        let descriptor = open(temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o644)
        if descriptor < 0 {
            throw .fileUnwritable(path: path, reason: Self.reason("open", errno))
        }
        var failure: DomainError?
        data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            var offset = 0
            while offset < bytes.count {
                let put = Darwin.write(
                    descriptor, bytes.baseAddress! + offset, bytes.count - offset)
                if put < 0 {
                    if errno == EINTR { continue }
                    failure = .fileUnwritable(path: path, reason: Self.reason("write", errno))
                    return
                }
                offset += put
            }
        }
        if failure == nil && fsync(descriptor) != 0 {
            failure = .fileUnwritable(path: path, reason: Self.reason("fsync", errno))
        }
        if close(descriptor) != 0 && failure == nil {
            failure = .fileUnwritable(path: path, reason: Self.reason("close", errno))
        }
        if failure == nil && rename(temporary, path) != 0 {
            failure = .fileUnwritable(path: path, reason: Self.reason("rename", errno))
        }
        if let failure {
            unlink(temporary)
            throw failure
        }
    }

    /// Creates a folder and every missing parent.
    public func createDirectory(at path: String) throws(DomainError) {
        if mkdir(path, 0o755) == 0 { return }
        let code = errno
        if code == EEXIST {
            var info = stat()
            if stat(path, &info) == 0 && (info.st_mode & S_IFMT) == S_IFDIR { return }
            throw .fileUnwritable(path: path, reason: "a file is in the way")
        }
        guard code == ENOENT, let parent = Self.parentPath(of: path) else {
            throw .fileUnwritable(path: path, reason: Self.reason("mkdir", code))
        }
        try createDirectory(at: parent)
        if mkdir(path, 0o755) != 0 && errno != EEXIST {
            throw .fileUnwritable(path: path, reason: Self.reason("mkdir", errno))
        }
    }

    /// Removes a file, a link or a folder tree. A link is removed without following it.
    public func removeItem(at path: String) throws(DomainError) {
        var info = stat()
        if lstat(path, &info) != 0 {
            throw .fileUnwritable(path: path, reason: Self.reason("lstat", errno))
        }
        if (info.st_mode & S_IFMT) == S_IFDIR {
            let children: [String]
            do {
                children = try topLevelNames(in: path)
            } catch {
                throw .fileUnwritable(path: path, reason: "cannot list the folder")
            }
            for child in children { try removeItem(at: path + "/" + child) }
            if rmdir(path) != 0 {
                throw .fileUnwritable(path: path, reason: Self.reason("rmdir", errno))
            }
        } else if unlink(path) != 0 {
            throw .fileUnwritable(path: path, reason: Self.reason("unlink", errno))
        }
    }

    /// Moves an item and replaces an existing destination.
    public func moveItem(at source: String, to destination: String) throws(DomainError) {
        if rename(source, destination) == 0 { return }
        let code = errno
        let blocked = [EEXIST, ENOTEMPTY, EISDIR, ENOTDIR].contains(code)
        guard blocked, exists(at: source), exists(at: destination) else {
            throw .fileUnwritable(path: destination, reason: Self.reason("rename", code))
        }
        try removeItem(at: destination)
        if rename(source, destination) != 0 {
            throw .fileUnwritable(path: destination, reason: Self.reason("rename", errno))
        }
    }

    // MARK: Helpers

    private static func reason(_ operation: String, _ code: Int32) -> String {
        "\(operation) failed: \(String(cString: strerror(code)))"
    }

    private static func parentPath(of path: String) -> String? {
        var trimmed = Substring(path)
        while trimmed.count > 1 && trimmed.hasSuffix("/") { trimmed = trimmed.dropLast() }
        guard let slash = trimmed.lastIndex(of: "/") else { return nil }
        if slash == trimmed.startIndex { return trimmed.count > 1 ? "/" : nil }
        return String(trimmed[trimmed.startIndex..<slash])
    }
}
