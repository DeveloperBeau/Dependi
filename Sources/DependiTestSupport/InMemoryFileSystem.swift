import DependiDomain
import Foundation

/// A file system in memory with files, folders, links and pipes. It follows the rules of `FileReading`.
public final class InMemoryFileSystem: FileReading, FileWriting, DirectoryListing,
    FileTreeArranging,
    @unchecked Sendable
{
    private enum Node: Sendable, Equatable {
        case file(Data)
        case directory
        case symlink(String)
        case namedPipe
    }

    private struct State: Sendable {
        var nodes: [String: Node] = ["/": .directory]
        var readOnlyPaths: Set<String> = []
    }

    private let state = LockedBox(State())

    /// Creates a file system that holds only the root folder.
    public init() {}

    /// Makes every write under a path fail, to test error handling.
    public func markReadOnly(_ path: String) {
        state.withValue { $0.readOnlyPaths.insert(Self.normalize(path)) }
    }

    // MARK: Paths

    private static func components(_ path: String) -> [String] {
        path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    }

    private static func normalize(_ path: String) -> String {
        var result: [String] = []
        for component in components(path) {
            if component == "." { continue }
            if component == ".." { _ = result.popLast() } else { result.append(component) }
        }
        return "/" + result.joined(separator: "/")
    }

    private static func join(_ parts: [String]) -> String { "/" + parts.joined(separator: "/") }

    /// Resolves links in every component. `followFinal` decides about the last one.
    private static func resolve(
        _ path: String, followFinal: Bool, nodes: [String: Node]
    ) throws(DomainError) -> String {
        var pending = components(normalize(path))
        var resolved: [String] = []
        var steps = 0
        while !pending.isEmpty {
            let name = pending.removeFirst()
            let candidate = join(resolved + [name])
            if case .symlink(let target)? = nodes[candidate], followFinal || !pending.isEmpty {
                steps += 1
                if steps > 40 { throw .symlinkLoop(path: path) }
                let targetParts = components(
                    normalize(target.hasPrefix("/") ? target : join(resolved) + "/" + target))
                resolved = []
                pending = targetParts + pending
            } else {
                resolved.append(name)
            }
        }
        return join(resolved)
    }

    // MARK: FileReading

    /// Implements `realPath` for `InMemoryFileSystem`.
    public func realPath(of path: String) throws(DomainError) -> String {
        try state.withValue { state throws(DomainError) in
            let resolved = try Self.resolve(path, followFinal: true, nodes: state.nodes)
            guard state.nodes[resolved] != nil else {
                throw .fileUnreadable(path: path, reason: "no such file")
            }
            return resolved
        }
    }

    /// Implements `readRegularFile` for `InMemoryFileSystem`.
    public func readRegularFile(at realPath: String, upToBytes limit: Int) throws(DomainError)
        -> Data
    {
        try state.withValue { state throws(DomainError) in
            let path = try Self.resolve(realPath, followFinal: false, nodes: state.nodes)
            switch state.nodes[path] {
            case .file(let data): return data.prefix(limit + 1)
            case nil: throw .fileUnreadable(path: realPath, reason: "no such file")
            default: throw .notRegularFile(path: realPath)
            }
        }
    }

    /// Implements `exists` for `InMemoryFileSystem`.
    public func exists(at path: String) -> Bool {
        state.withValue { state in
            guard let resolved = try? Self.resolve(path, followFinal: false, nodes: state.nodes)
            else {
                return false
            }
            return state.nodes[resolved] != nil
        }
    }

    // MARK: DirectoryListing

    /// Implements `topLevelNames` for `InMemoryFileSystem`.
    public func topLevelNames(in directory: String) throws(DomainError) -> [String] {
        try state.withValue { state throws(DomainError) in
            let resolved = try Self.resolve(directory, followFinal: true, nodes: state.nodes)
            guard case .directory? = state.nodes[resolved] else {
                throw .fileUnreadable(path: directory, reason: "not a folder")
            }
            let depth = Self.components(resolved).count
            return state.nodes.keys.compactMap { key -> String? in
                let parts = Self.components(key)
                guard parts.count == depth + 1, Self.join(Array(parts.prefix(depth))) == resolved
                else { return nil }
                return parts.last
            }.sorted()
        }
    }

    // MARK: FileWriting

    private static func checkWritable(_ path: String, state: State) throws(DomainError) {
        for readOnly in state.readOnlyPaths where path == readOnly || path.hasPrefix(readOnly + "/")
        {
            throw .fileUnwritable(path: path, reason: "read-only")
        }
    }

    /// Implements `write` for `InMemoryFileSystem`.
    public func write(_ data: Data, toPath path: String) throws(DomainError) {
        try state.withValue { state throws(DomainError) in
            let target = try Self.resolve(path, followFinal: false, nodes: state.nodes)
            try Self.checkWritable(target, state: state)
            let parent = Self.join(Array(Self.components(target).dropLast()))
            guard case .directory? = state.nodes[parent] else {
                throw .fileUnwritable(path: path, reason: "the folder does not exist")
            }
            state.nodes[target] = .file(data)
        }
    }

    /// Implements `createDirectory` for `InMemoryFileSystem`.
    public func createDirectory(at path: String) throws(DomainError) {
        try state.withValue { state throws(DomainError) in
            let target = try Self.resolve(path, followFinal: true, nodes: state.nodes)
            try Self.checkWritable(target, state: state)
            var built: [String] = []
            for name in Self.components(target) {
                built.append(name)
                let current = Self.join(built)
                switch state.nodes[current] {
                case nil: state.nodes[current] = .directory
                case .directory?: continue
                default: throw .fileUnwritable(path: path, reason: "a file is in the way")
                }
            }
        }
    }

    /// Implements `removeItem` for `InMemoryFileSystem`.
    public func removeItem(at path: String) throws(DomainError) {
        try state.withValue { state throws(DomainError) in
            let target = try Self.resolve(path, followFinal: false, nodes: state.nodes)
            try Self.checkWritable(target, state: state)
            guard state.nodes[target] != nil else {
                throw .fileUnwritable(path: path, reason: "no such file")
            }
            for key in state.nodes.keys where key == target || key.hasPrefix(target + "/") {
                state.nodes[key] = nil
            }
        }
    }

    /// Implements `moveItem` for `InMemoryFileSystem`.
    public func moveItem(at source: String, to destination: String) throws(DomainError) {
        try state.withValue { state throws(DomainError) in
            let from = try Self.resolve(source, followFinal: false, nodes: state.nodes)
            let to = try Self.resolve(destination, followFinal: false, nodes: state.nodes)
            try Self.checkWritable(from, state: state)
            try Self.checkWritable(to, state: state)
            guard state.nodes[from] != nil else {
                throw .fileUnwritable(path: source, reason: "no such file")
            }
            let parent = Self.join(Array(Self.components(to).dropLast()))
            guard case .directory? = state.nodes[parent] else {
                throw .fileUnwritable(path: destination, reason: "the folder does not exist")
            }
            for key in state.nodes.keys where key == to || key.hasPrefix(to + "/") {
                state.nodes[key] = nil
            }
            for key in state.nodes.keys.sorted() where key == from || key.hasPrefix(from + "/") {
                let moved = to + key.dropFirst(from.count)
                state.nodes[moved] = state.nodes[key]
                state.nodes[key] = nil
            }
        }
    }

    // MARK: FileTreeArranging

    /// Implements `addFile` for `InMemoryFileSystem`.
    public func addFile(at path: String, contents: Data) throws {
        try write(contents, toPath: path)
    }

    /// Implements `addDirectory` for `InMemoryFileSystem`.
    public func addDirectory(at path: String) throws {
        try createDirectory(at: path)
    }

    /// Implements `addSymlink` for `InMemoryFileSystem`.
    public func addSymlink(at path: String, pointingTo target: String) throws {
        try state.withValue { state throws(DomainError) in
            let resolved = try Self.resolve(path, followFinal: false, nodes: state.nodes)
            state.nodes[resolved] = .symlink(target)
        }
    }

    /// Implements `addNamedPipe` for `InMemoryFileSystem`.
    public func addNamedPipe(at path: String) throws {
        try state.withValue { state throws(DomainError) in
            let resolved = try Self.resolve(path, followFinal: false, nodes: state.nodes)
            state.nodes[resolved] = .namedPipe
        }
    }
}
