import DependiDomain
import DependiFileSystem
import Foundation
import Testing

@Suite("Disk file system operations")
struct DiskOperationTests {
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

    @Test("a link in the last component is refused even when it points to a regular file")
    func lastComponentLinkIsRefused() throws {
        try TempFolder.run { temp in
            try arranger.addFile(at: temp.real + "/target", contents: Data("abc".utf8))
            try arranger.addSymlink(at: temp.real + "/link", pointingTo: "target")
            let outcome1 = caught {
                try disk.readRegularFile(at: temp.real + "/link", upToBytes: 10)
            }
            #expect(outcome1 == .notRegularFile(path: temp.real + "/link"))
            #expect(
                (try? disk.readRegularFile(at: temp.real + "/target", upToBytes: 10))
                    == Data("abc".utf8))
        }
    }

    @Test("a folder is refused as not a regular file")
    func folderIsRefused() throws {
        try TempFolder.run { temp in
            try arranger.addDirectory(at: temp.real + "/dir")
            let outcome2 = caught {
                try disk.readRegularFile(at: temp.real + "/dir", upToBytes: 10)
            }
            #expect(outcome2 == .notRegularFile(path: temp.real + "/dir"))
        }
    }

    @Test("a named pipe is refused without hanging")
    func pipeIsRefused() throws {
        try TempFolder.run { temp in
            try arranger.addNamedPipe(at: temp.real + "/pipe")
            let outcome3 = caught {
                try disk.readRegularFile(at: temp.real + "/pipe", upToBytes: 10)
            }
            #expect(outcome3 == .notRegularFile(path: temp.real + "/pipe"))
        }
    }

    @Test("a missing path has no real path and cannot be read")
    func missingPathHasNoRealPath() throws {
        try TempFolder.run { temp in
            let outcome4 = caught { try disk.realPath(of: temp.real + "/absent") }
            #expect(outcome4 == .fileNotFound(path: temp.real + "/absent"))
            let outcome5 = caught {
                try disk.readRegularFile(at: temp.real + "/absent", upToBytes: 1)
            }
            #expect(outcome5 == .fileNotFound(path: temp.real + "/absent"))
            try arranger.addFile(at: temp.real + "/plain", contents: Data())
            let outcome6 = caught { try disk.realPath(of: temp.real + "/plain/inner") }
            #expect(outcome6 == .fileNotFound(path: temp.real + "/plain/inner"))
        }
    }

    @Test("a loop of links is reported as a loop")
    func loopIsReported() throws {
        try TempFolder.run { temp in
            try arranger.addSymlink(at: temp.real + "/a", pointingTo: "b")
            try arranger.addSymlink(at: temp.real + "/b", pointingTo: "a")
            let outcome7 = caught { try disk.realPath(of: temp.real + "/a") }
            #expect(outcome7 == .symlinkLoop(path: temp.real + "/a"))
        }
    }

    @Test("a dangling link exists and a missing path does not")
    func danglingLinkExists() throws {
        try TempFolder.run { temp in
            try arranger.addSymlink(at: temp.real + "/dangling", pointingTo: "nowhere")
            #expect(disk.exists(at: temp.real + "/dangling"))
            #expect(!disk.exists(at: temp.real + "/nowhere"))
        }
    }

    @Test("listing is sorted and does not look inside subfolders")
    func listingIsSorted() throws {
        try TempFolder.run { temp in
            let names = (0..<40).map { "n\(($0 * 17) % 40)" }
            for name in names { try arranger.addFile(at: temp.real + "/" + name, contents: Data()) }
            try arranger.addDirectory(at: temp.real + "/sub")
            try arranger.addFile(at: temp.real + "/sub/deep", contents: Data())
            let expected = (names + ["sub"]).sorted()
            #expect(try disk.topLevelNames(in: temp.real) == expected)
            #expect(expected.count == 41)
            #expect(!expected.contains("deep"))
        }
    }

    @Test("listing a file or a missing folder fails with the right case")
    func listingFailures() throws {
        try TempFolder.run { temp in
            try arranger.addFile(at: temp.real + "/f", contents: Data())
            let missing = caught { try disk.topLevelNames(in: temp.real + "/absent") }
            #expect(missing == .fileNotFound(path: temp.real + "/absent"))
            let listed = caught { try disk.topLevelNames(in: temp.real + "/f") }
            guard case .fileUnreadable(let path, let reason)? = listed else {
                Issue.record("expected fileUnreadable but got \(String(describing: listed))")
                return
            }
            #expect(path == temp.real + "/f")
            #expect(reason.contains("opendir"))
            #expect(reason.contains("Not a directory"))
        }
    }

    @Test("a move replaces a file, a folder with content, and needs the destination parent")
    func moveReplacesDestination() throws {
        try TempFolder.run { temp in
            try arranger.addFile(at: temp.real + "/src", contents: Data("new".utf8))
            try arranger.addDirectory(at: temp.real + "/dest/inner")
            try arranger.addFile(at: temp.real + "/dest/inner/old", contents: Data("old".utf8))
            try disk.moveItem(at: temp.real + "/src", to: temp.real + "/dest")
            #expect(
                (try? disk.readRegularFile(at: temp.real + "/dest", upToBytes: 10))
                    == Data("new".utf8))
            #expect(!disk.exists(at: temp.real + "/src"))

            try arranger.addDirectory(at: temp.real + "/folderA/x")
            try arranger.addDirectory(at: temp.real + "/folderB/y")
            try arranger.addFile(at: temp.real + "/folderB/y/z", contents: Data())
            try disk.moveItem(at: temp.real + "/folderA", to: temp.real + "/folderB")
            #expect(try disk.topLevelNames(in: temp.real + "/folderB") == ["x"])

            try arranger.addFile(at: temp.real + "/s2", contents: Data())
            if case .fileUnwritable? = caught({
                try disk.moveItem(at: temp.real + "/s2", to: temp.real + "/missing/s2")
            }) {
            } else {
                Issue.record("expected fileUnwritable for a missing destination parent")
            }
            if case .fileUnwritable? = caught({
                try disk.moveItem(at: temp.real + "/nothing", to: temp.real + "/s3")
            }) {
            } else {
                Issue.record("expected fileUnwritable for a missing source")
            }
        }
    }

    @Test("removing a link removes the link and keeps what it points to")
    func removingLinkKeepsTarget() throws {
        try TempFolder.run { temp in
            try arranger.addFile(at: temp.real + "/outside/keep", contents: Data("k".utf8))
            try arranger.addDirectory(at: temp.real + "/tree")
            try arranger.addSymlink(
                at: temp.real + "/tree/link", pointingTo: temp.real + "/outside")
            try arranger.addFile(at: temp.real + "/tree/file", contents: Data())
            try disk.removeItem(at: temp.real + "/tree/link")
            #expect(!disk.exists(at: temp.real + "/tree/link"))
            #expect(disk.exists(at: temp.real + "/outside/keep"))
            try arranger.addSymlink(
                at: temp.real + "/tree/link2", pointingTo: temp.real + "/outside")
            try disk.removeItem(at: temp.real + "/tree")
            #expect(!disk.exists(at: temp.real + "/tree"))
            #expect(disk.exists(at: temp.real + "/outside/keep"))
        }
    }

    @Test("removing a missing path fails with fileUnwritable")
    func removingMissingPathFails() throws {
        try TempFolder.run { temp in
            if case .fileUnwritable(let path, let reason)? = caught({
                try disk.removeItem(at: temp.real + "/absent")
            }) {
                #expect(path == temp.real + "/absent")
                #expect(reason.contains("No such file or directory"))
            } else {
                Issue.record("expected fileUnwritable")
            }
        }
    }

    @Test("creating a folder that exists succeeds and a file in the way fails")
    func createDirectoryEdges() throws {
        try TempFolder.run { temp in
            try disk.createDirectory(at: temp.real + "/a/b/c")
            try disk.createDirectory(at: temp.real + "/a/b/c")
            try disk.createDirectory(at: temp.real + "/a/b/")
            #expect(try disk.topLevelNames(in: temp.real + "/a/b") == ["c"])
            try arranger.addFile(at: temp.real + "/file", contents: Data())
            if case .fileUnwritable? = caught({ try disk.createDirectory(at: temp.real + "/file") })
            {
            } else {
                Issue.record("expected fileUnwritable")
            }
            if case .fileUnwritable? = caught({
                try disk.createDirectory(at: temp.real + "/file/inner")
            }) {
            } else {
                Issue.record("expected fileUnwritable under a file")
            }
        }
    }
}

extension DiskOperationTests {
    @Test("the modification date is the date the file system reports, and a link is not followed")
    func modificationDateOfALinkIsTheLinksOwn() throws {
        try TempFolder.run { temp in
            let old = Date(timeIntervalSince1970: 1_000_000)
            try arranger.addFile(at: temp.real + "/target", contents: Data("a".utf8))
            try FileManager.default.setAttributes(
                [.modificationDate: old], ofItemAtPath: temp.real + "/target")
            try arranger.addSymlink(at: temp.real + "/link", pointingTo: "target")
            let target = try #require(disk.modificationDate(of: temp.real + "/target"))
            #expect(abs(target.timeIntervalSince(old)) < 1)
            let link = try #require(disk.modificationDate(of: temp.real + "/link"))
            #expect(link.timeIntervalSince(old) > 1_000)
            #expect(disk.modificationDate(of: temp.real + "/absent") == nil)
        }
    }
}
