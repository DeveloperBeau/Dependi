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
}
