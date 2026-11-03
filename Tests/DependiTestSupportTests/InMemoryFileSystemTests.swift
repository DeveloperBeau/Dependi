import DependiDomain
import DependiTestSupport
import Foundation
import Testing

@Suite("In-memory file system", .timeLimit(.minutes(1)))
struct InMemoryFileSystemTests {
    @Test("the double passes the shared file behavior suite")
    func doublePassesBehaviorSuite() {
        let fileSystem = InMemoryFileSystem()
        try! fileSystem.addDirectory(at: "/work")
        let problems = FileSystemBehavior.problems(
            root: "/work", arranger: fileSystem, reader: fileSystem, lister: fileSystem,
            writer: fileSystem)
        #expect(problems.isEmpty, "\(problems)")
    }

    @Test("the suite passes when the root is reached through a linked folder")
    func suitePassesThroughLinkedRoot() throws {
        let fileSystem = InMemoryFileSystem()
        try fileSystem.addDirectory(at: "/private/var/work")
        try fileSystem.addSymlink(at: "/var", pointingTo: "/private/var")
        let problems = FileSystemBehavior.problems(
            root: "/var/work", arranger: fileSystem, reader: fileSystem, lister: fileSystem,
            writer: fileSystem)
        #expect(problems.isEmpty, "\(problems)")
    }

    @Test("the suite fails for a reader that ignores the size limit")
    func suiteDetectsLimitIgnored() throws {
        struct Unbounded: FileReading {
            let inner: InMemoryFileSystem
            func realPath(of path: String) throws(DomainError) -> String {
                try inner.realPath(of: path)
            }
            func readRegularFile(at realPath: String, upToBytes limit: Int) throws(DomainError)
                -> Data
            {
                try inner.readRegularFile(at: realPath, upToBytes: Int.max - 1)
            }
            func exists(at path: String) -> Bool { inner.exists(at: path) }
        }
        let fileSystem = InMemoryFileSystem()
        try fileSystem.addDirectory(at: "/work")
        let problems = FileSystemBehavior.problems(
            root: "/work", arranger: fileSystem, reader: Unbounded(inner: fileSystem),
            lister: fileSystem, writer: fileSystem)
        #expect(
            problems == [
                "a limit below the size returns limit plus one bytes",
                "a negative limit is treated as zero and returns one byte",
            ])
    }

    @Test("the suite fails for a reader that follows a link in the last component")
    func suiteDetectsFollowedLink() throws {
        struct Following: FileReading {
            let inner: InMemoryFileSystem
            func realPath(of path: String) throws(DomainError) -> String {
                try inner.realPath(of: path)
            }
            func readRegularFile(at realPath: String, upToBytes limit: Int) throws(DomainError)
                -> Data
            {
                try inner.readRegularFile(at: try inner.realPath(of: realPath), upToBytes: limit)
            }
            func exists(at path: String) -> Bool { inner.exists(at: path) }
        }
        let fileSystem = InMemoryFileSystem()
        try fileSystem.addDirectory(at: "/work")
        let problems = FileSystemBehavior.problems(
            root: "/work", arranger: fileSystem, reader: Following(inner: fileSystem),
            lister: fileSystem, writer: fileSystem)
        #expect(problems.contains { $0.hasPrefix("a link in the last component is refused") })
    }

    @Test("a loop of links is reported and a long chain still resolves")
    func loopsAndChains() throws {
        let fileSystem = InMemoryFileSystem()
        try fileSystem.addDirectory(at: "/work")
        try fileSystem.addFile(at: "/work/end", contents: Data("x".utf8))
        var previous = "/work/end"
        for index in 0..<30 {
            try fileSystem.addSymlink(at: "/work/hop\(index)", pointingTo: previous)
            previous = "/work/hop\(index)"
        }
        #expect(try fileSystem.realPath(of: "/work/hop29") == "/work/end")
        try fileSystem.addSymlink(at: "/work/self", pointingTo: "/work/self")
        #expect(throws: DomainError.symlinkLoop(path: "/work/self")) {
            try fileSystem.realPath(of: "/work/self")
        }
    }

    @Test("a chain of 32 links resolves and 33 is a loop, as on the real disk")
    func linkChainLimitMatchesDisk() throws {
        let fileSystem = InMemoryFileSystem()
        try fileSystem.addDirectory(at: "/work")
        try fileSystem.addFile(at: "/work/end", contents: Data("x".utf8))
        var previous = "/work/end"
        for index in 1...33 {
            try fileSystem.addSymlink(at: "/work/hop\(index)", pointingTo: previous)
            previous = "/work/hop\(index)"
        }
        #expect(try fileSystem.realPath(of: "/work/hop32") == "/work/end")
        #expect(throws: DomainError.symlinkLoop(path: "/work/hop33")) {
            try fileSystem.realPath(of: "/work/hop33")
        }
    }

    @Test("a write onto a folder fails and keeps the folder and its children")
    func writeOntoFolderFails() throws {
        let fileSystem = InMemoryFileSystem()
        try fileSystem.addDirectory(at: "/work/folder")
        try fileSystem.addFile(at: "/work/folder/child", contents: Data("c".utf8))
        #expect(throws: DomainError.self) {
            try fileSystem.write(Data("new".utf8), toPath: "/work/folder")
        }
        #expect(
            try fileSystem.readRegularFile(at: "/work/folder/child", upToBytes: 10)
                == Data("c".utf8))
        // A write onto a file or a missing name still works.
        try fileSystem.write(Data("a".utf8), toPath: "/work/file")
        try fileSystem.write(Data("b".utf8), toPath: "/work/file")
        #expect(try fileSystem.readRegularFile(at: "/work/file", upToBytes: 10) == Data("b".utf8))
    }

    @Test("a negative or huge read limit neither traps nor overflows")
    func extremeReadLimits() throws {
        let fileSystem = InMemoryFileSystem()
        try fileSystem.addDirectory(at: "/work")
        try fileSystem.addFile(at: "/work/file", contents: Data("abc".utf8))
        for limit in [Int.min, -1] {
            #expect(
                try fileSystem.readRegularFile(at: "/work/file", upToBytes: limit) == Data("a".utf8)
            )
        }
        #expect(try fileSystem.readRegularFile(at: "/work/file", upToBytes: 0) == Data("a".utf8))
        for limit in [Int.max - 1, Int.max] {
            #expect(
                try fileSystem.readRegularFile(at: "/work/file", upToBytes: limit)
                    == Data("abc".utf8))
        }
    }

    @Test("the suite fails for a writer that replaces a folder with a file")
    func suiteDetectsWriteOntoFolder() throws {
        struct Replacing: FileWriting {
            let inner: InMemoryFileSystem
            func write(_ data: Data, toPath path: String) throws(DomainError) {
                if inner.exists(at: path), (try? inner.topLevelNames(in: path)) != nil {
                    try inner.removeItem(at: path)
                }
                try inner.write(data, toPath: path)
            }
            func createDirectory(at path: String) throws(DomainError) {
                try inner.createDirectory(at: path)
            }
            func removeItem(at path: String) throws(DomainError) { try inner.removeItem(at: path) }
            func moveItem(at source: String, to destination: String) throws(DomainError) {
                try inner.moveItem(at: source, to: destination)
            }
        }
        let fileSystem = InMemoryFileSystem()
        try fileSystem.addDirectory(at: "/work")
        let problems = FileSystemBehavior.problems(
            root: "/work", arranger: fileSystem, reader: fileSystem, lister: fileSystem,
            writer: Replacing(inner: fileSystem))
        #expect(
            problems.first
                == "a write onto a folder fails: expected fileUnwritable but nothing failed")
    }

    @Test("a read-only folder refuses writes, moves and removals under it")
    func readOnlyRefusesChanges() throws {
        let fileSystem = InMemoryFileSystem()
        try fileSystem.addDirectory(at: "/work/locked")
        try fileSystem.addFile(at: "/work/locked/a", contents: Data())
        fileSystem.markReadOnly("/work/locked")
        #expect(throws: DomainError.fileUnwritable(path: "/work/locked/b", reason: "read-only")) {
            try fileSystem.write(Data(), toPath: "/work/locked/b")
        }
        #expect(throws: DomainError.fileUnwritable(path: "/work/locked/a", reason: "read-only")) {
            try fileSystem.removeItem(at: "/work/locked/a")
        }
        #expect(throws: DomainError.fileUnwritable(path: "/work/locked/a", reason: "read-only")) {
            try fileSystem.moveItem(at: "/work/locked/a", to: "/work/elsewhere")
        }
        #expect(fileSystem.exists(at: "/work/locked/a"))
    }

    @Test("a sibling folder with a similar name is not treated as read-only")
    func readOnlyIsMatchedByComponent() throws {
        let fileSystem = InMemoryFileSystem()
        try fileSystem.addDirectory(at: "/work/locked")
        try fileSystem.addDirectory(at: "/work/locked-other")
        fileSystem.markReadOnly("/work/locked")
        try fileSystem.write(Data("ok".utf8), toPath: "/work/locked-other/file")
        #expect(fileSystem.exists(at: "/work/locked-other/file"))
    }
}
