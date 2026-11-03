import DependiDomain
import DependiFileSystem
import DependiTestSupport
import Foundation
import Testing

@Suite("Disk file system behavior")
struct DiskBehaviorTests {
    private func problems(root: String) -> [String] {
        let disk = DiskFileSystem()
        return FileSystemBehavior.problems(
            root: root, arranger: DiskTreeArranger(), reader: disk, lister: disk, writer: disk)
    }

    @Test("the disk passes the shared behavior suite in a plain temporary folder")
    func passesSuiteOnPlainRoot() throws {
        try TempFolder.run { temp in
            let found = problems(root: temp.root)
            #expect(found.isEmpty, "\(found)")
        }
    }

    @Test("the disk passes the shared behavior suite when the root is reached through a link")
    func passesSuiteOnLinkedRoot() throws {
        try TempFolder.run { temp in
            let base = temp.root + "/base"
            let linked = temp.root + "/linked"
            try DiskTreeArranger().addDirectory(at: base)
            try DiskTreeArranger().addSymlink(at: linked, pointingTo: base)
            #expect(try DiskFileSystem().realPath(of: linked) == temp.real + "/base")
            #expect(try DiskFileSystem().realPath(of: linked) != linked)
            let found = problems(root: linked)
            #expect(found.isEmpty, "\(found)")
        }
    }

    @Test("the suite fails for a disk reader that follows a link in the last component")
    func suiteDetectsFollowingReader() throws {
        struct Following: FileReading {
            func realPath(of path: String) throws(DomainError) -> String {
                try DiskFileSystem().realPath(of: path)
            }
            func readRegularFile(at realPath: String, upToBytes limit: Int) throws(DomainError)
                -> Data
            {
                guard let data = FileManager.default.contents(atPath: realPath) else {
                    throw .fileNotFound(path: realPath)
                }
                return data.prefix(limit + 1)
            }
            func exists(at path: String) -> Bool { DiskFileSystem().exists(at: path) }
        }
        try TempFolder.run { temp in
            let disk = DiskFileSystem()
            let found = FileSystemBehavior.problems(
                root: temp.root, arranger: DiskTreeArranger(), reader: Following(), lister: disk,
                writer: disk)
            #expect(found.contains { $0.hasPrefix("a link in the last component is refused") })
        }
    }

    private func isExecutable(_ path: String) -> Bool {
        var info = stat()
        return stat(path, &info) == 0 && (info.st_mode & 0o111) != 0
    }

    @Test("the disk passes the shared executable marking rules")
    func passesExecutableSuite() throws {
        try TempFolder.run { temp in
            let disk = DiskFileSystem()
            let found = FileSystemBehavior.executableProblems(
                root: temp.root, reader: disk, writer: disk, executables: disk,
                isExecutable: isExecutable)
            #expect(found.isEmpty, "\(found)")
        }
    }

    @Test("marking a file executable sets the mode to rwxr-xr-x and follows a link")
    func makeExecutableSetsMode() throws {
        try TempFolder.run { temp in
            let disk = DiskFileSystem()
            try DiskTreeArranger().addFile(at: temp.real + "/tool", contents: Data("x".utf8))
            chmod(temp.real + "/tool", 0o600)
            try DiskTreeArranger().addSymlink(
                at: temp.real + "/link", pointingTo: temp.real + "/tool")
            try disk.makeExecutable(at: temp.real + "/link")
            var info = stat()
            #expect(stat(temp.real + "/tool", &info) == 0)
            #expect(info.st_mode & 0o777 == 0o755)
        }
    }

    @Test(
        "a chmod that the system refuses is reported as fileUnwritable with the system text",
        .enabled(
            if: geteuid() != 0, "a root user can change any mode, so the case cannot be set up")
    )
    func makeExecutableRefused() throws {
        try TempFolder.run { temp in
            let disk = DiskFileSystem()
            try DiskTreeArranger().addDirectory(at: temp.real + "/locked")
            try DiskTreeArranger().addFile(
                at: temp.real + "/locked/tool", contents: Data("x".utf8))
            chmod(temp.real + "/locked", 0o000)
            defer { chmod(temp.real + "/locked", 0o755) }
            do {
                try disk.makeExecutable(at: temp.real + "/locked/tool")
                Issue.record("expected fileUnwritable")
            } catch let error as DomainError {
                guard case .fileUnwritable(let path, let reason) = error else {
                    Issue.record("expected fileUnwritable but got \(error)")
                    return
                }
                #expect(path == temp.real + "/locked/tool")
                #expect(reason.contains("chmod failed"))
                #expect(reason.contains("Permission denied"))
            }
        }
    }

    @Test("the executable suite fails for a marker that does nothing")
    func diskExecutableSuiteDetectsNoopMarker() throws {
        struct Noop: ExecutableMarking {
            func makeExecutable(at path: String) throws(DomainError) {}
        }
        try TempFolder.run { temp in
            let disk = DiskFileSystem()
            let found = FileSystemBehavior.executableProblems(
                root: temp.root, reader: disk, writer: disk, executables: Noop(),
                isExecutable: isExecutable)
            #expect(found.contains("a marked file is executable"))
        }
    }
}
