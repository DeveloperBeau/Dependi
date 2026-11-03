import DependiDomain
import DependiFileSystem
import Foundation
import Testing

@Suite("Disk file system failures")
struct DiskFailureTests {
    private let disk = DiskFileSystem()
    private let arranger = DiskTreeArranger()

    private func caught<T>(_ body: () throws -> T) -> DomainError? {
        do {
            _ = try body()
            return nil
        } catch let error as DomainError {
            return error
        } catch {
            Issue.record("unexpected error \(error)")
            return nil
        }
    }

    @Test(
        "an unreadable file is reported as fileUnreadable with the system text",
        .enabled(if: geteuid() != 0, "a root user can read any file, so the case cannot be set up"))
    func unreadableFile() throws {
        try TempFolder.run { temp in
            try arranger.addFile(at: temp.real + "/secret", contents: Data("x".utf8))
            chmod(temp.real + "/secret", 0o000)
            if case .fileUnreadable(let path, let reason)? = caught({
                try disk.readRegularFile(at: temp.real + "/secret", upToBytes: 10)
            }) {
                #expect(path == temp.real + "/secret")
                #expect(reason.contains("Permission denied"))
            } else {
                Issue.record("expected fileUnreadable")
            }
        }
    }

    @Test("a write into a missing folder fails and leaves nothing behind")
    func writeIntoMissingFolder() throws {
        try TempFolder.run { (temp: TempFolder) throws -> Void in
            let target = temp.real + "/no-folder/file"
            if case .fileUnwritable(let path, let reason)? = caught({
                try disk.write(Data("x".utf8), toPath: target)
            }) {
                #expect(path == target)
                #expect(reason.contains("No such file or directory"))
            } else {
                Issue.record("expected fileUnwritable")
            }
            #expect(try disk.topLevelNames(in: temp.real).isEmpty)
        }
    }

    @Test(
        "a write into a read-only folder is refused and leaves the folder unchanged",
        .enabled(if: geteuid() != 0, "a root user can write anywhere, so the case cannot be set up")
    )
    func writeIntoReadOnlyFolder() throws {
        try TempFolder.run { (temp: TempFolder) throws -> Void in
            try arranger.addDirectory(at: temp.real + "/locked")
            chmod(temp.real + "/locked", 0o555)
            if case .fileUnwritable(_, let reason)? = caught({
                try disk.write(Data("x".utf8), toPath: temp.real + "/locked/file")
            }) {
                #expect(reason.contains("Permission denied"))
            } else {
                Issue.record("expected fileUnwritable")
            }
            #expect(try disk.topLevelNames(in: temp.real + "/locked").isEmpty)
        }
    }

    @Test("a read below a regular file is reported as notRegularFile and runs for every user")
    func readBelowRegularFile() throws {
        try TempFolder.run { temp in
            try arranger.addFile(at: temp.real + "/plain", contents: Data("x".utf8))
            let target = temp.real + "/plain/child"
            if case .notRegularFile(let path)? = caught({
                try disk.readRegularFile(at: target, upToBytes: 10)
            }) {
                #expect(path == target)
            } else {
                Issue.record("expected notRegularFile")
            }
        }
    }

    @Test("a write below a regular file is refused and leaves the folder unchanged")
    func writeBelowRegularFile() throws {
        try TempFolder.run { (temp: TempFolder) throws -> Void in
            try arranger.addFile(at: temp.real + "/plain", contents: Data("x".utf8))
            let target = temp.real + "/plain/child"
            if case .fileUnwritable(let path, let reason)? = caught({
                try disk.write(Data("y".utf8), toPath: target)
            }) {
                #expect(path == target)
                #expect(reason.contains("Not a directory"))
            } else {
                Issue.record("expected fileUnwritable")
            }
            #expect(try disk.topLevelNames(in: temp.real) == ["plain"])
            #expect(
                (try? disk.readRegularFile(at: temp.real + "/plain", upToBytes: 10))
                    == Data("x".utf8))
        }
    }

    @Test("a write replaces the file and leaves no temporary file")
    func writeIsCleanAndReplaces() throws {
        try TempFolder.run { temp in
            try disk.write(Data("one".utf8), toPath: temp.real + "/f")
            try disk.write(Data("two".utf8), toPath: temp.real + "/f")
            #expect(try disk.topLevelNames(in: temp.real) == ["f"])
            #expect(
                (try? disk.readRegularFile(at: temp.real + "/f", upToBytes: 10))
                    == Data("two".utf8))
        }
    }

    @Test("a large file read stops after limit plus one bytes")
    func readStopsAfterLimitPlusOne() throws {
        try TempFolder.run { temp in
            let path = temp.real + "/huge"
            try arranger.addFile(at: path, contents: Data())
            // A sparse file of 1 GiB. Reading it all would need a gigabyte of memory.
            let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
            try handle.truncate(atOffset: 1 << 30)
            try handle.close()
            let data = try disk.readRegularFile(at: path, upToBytes: 100)
            #expect(data.count == 101)
            #expect(data.allSatisfy { $0 == 0 })
            #expect(try disk.readRegularFile(at: path, upToBytes: 70_000).count == 70_001)
            #expect(try disk.readRegularFile(at: path, upToBytes: 0).count == 1)
        }
    }
}
