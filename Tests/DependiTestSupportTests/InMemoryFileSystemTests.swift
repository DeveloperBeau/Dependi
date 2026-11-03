import DependiDomain
import DependiTestSupport
import Foundation
import Testing

@Suite("In-memory file system")
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

    @Test("the double passes the shared executable marking rules")
    func doublePassesExecutableSuite() throws {
        let fileSystem = InMemoryFileSystem()
        try fileSystem.addDirectory(at: "/work")
        let problems = FileSystemBehavior.executableProblems(
            root: "/work", reader: fileSystem, writer: fileSystem, executables: fileSystem,
            isExecutable: { fileSystem.isExecutable(at: $0) })
        #expect(problems.isEmpty, "\(problems)")
    }

    @Test("the executable suite fails for a marker that does nothing")
    func executableSuiteDetectsNoopMarker() throws {
        struct Noop: ExecutableMarking {
            func makeExecutable(at path: String) throws(DomainError) {}
        }
        let fileSystem = InMemoryFileSystem()
        try fileSystem.addDirectory(at: "/work")
        let problems = FileSystemBehavior.executableProblems(
            root: "/work", reader: fileSystem, writer: fileSystem, executables: Noop(),
            isExecutable: { fileSystem.isExecutable(at: $0) })
        #expect(problems.contains("a marked file is executable"))
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
        #expect(problems == ["a limit below the size returns limit plus one bytes"])
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
