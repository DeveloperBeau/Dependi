import DependiDomain
import Foundation

/// One behavior suite for the file interfaces. The double and the real file system must both pass it.
public enum FileSystemBehavior {
    private static func kind(_ error: DomainError) -> String {
        switch error {
        case .fileNotFound: return "fileNotFound"
        case .fileUnreadable: return "fileUnreadable"
        case .notRegularFile: return "notRegularFile"
        case .fileUnwritable: return "fileUnwritable"
        case .symlinkLoop: return "symlinkLoop"
        default: return "other"
        }
    }

    /// Runs the suite inside `root`, which must be an empty folder that can be written.
    /// It returns one sentence for each rule that failed. An empty list means success.
    public static func problems(
        root: String,
        arranger: some FileTreeArranging,
        reader: some FileReading,
        lister: some DirectoryListing,
        writer: some FileWriting
    ) -> [String] {
        var problems: [String] = []

        func check(_ rule: String, _ condition: Bool) {
            if !condition { problems.append(rule) }
        }
        func expectFailure(_ rule: String, kind expected: String, _ body: () throws -> Void) {
            do {
                try body()
                problems.append("\(rule): expected \(expected) but nothing failed")
            } catch let error as DomainError {
                let actual = kind(error)
                if actual != expected {
                    problems.append("\(rule): expected \(expected) but got \(actual)")
                }
            } catch {
                problems.append("\(rule): expected \(expected) but got \(error)")
            }
        }

        do {
            let realRoot = try reader.realPath(of: root)
            let bytes = Data((0..<10).map { UInt8($0 + 65) })

            // Regular files
            try arranger.addFile(at: root + "/file.txt", contents: bytes)
            check(
                "a regular file is read in full",
                (try? reader.readRegularFile(at: realRoot + "/file.txt", upToBytes: 20)) == bytes)
            check(
                "a limit below the size returns limit plus one bytes",
                (try? reader.readRegularFile(at: realRoot + "/file.txt", upToBytes: 4))
                    == bytes.prefix(5))
            check(
                "a limit equal to the size returns the whole file",
                (try? reader.readRegularFile(at: realRoot + "/file.txt", upToBytes: 10)) == bytes)
            expectFailure("a missing file cannot be read", kind: "fileNotFound") {
                _ = try reader.readRegularFile(at: realRoot + "/absent", upToBytes: 4)
            }

            // Links, folders and pipes
            try arranger.addSymlink(at: root + "/link", pointingTo: realRoot + "/file.txt")
            expectFailure("a link in the last component is refused", kind: "notRegularFile") {
                _ = try reader.readRegularFile(at: root + "/link", upToBytes: 4)
            }
            try arranger.addDirectory(at: root + "/folder")
            expectFailure("a folder is refused", kind: "notRegularFile") {
                _ = try reader.readRegularFile(at: realRoot + "/folder", upToBytes: 4)
            }
            try arranger.addNamedPipe(at: root + "/pipe")
            expectFailure("a named pipe is refused", kind: "notRegularFile") {
                _ = try reader.readRegularFile(at: realRoot + "/pipe", upToBytes: 4)
            }

            // Real paths
            try arranger.addSymlink(at: root + "/chain-a", pointingTo: realRoot + "/chain-b")
            try arranger.addSymlink(at: root + "/chain-b", pointingTo: realRoot + "/file.txt")
            check(
                "a chain of links resolves to the file",
                (try? reader.realPath(of: root + "/chain-a")) == realRoot + "/file.txt")
            try arranger.addDirectory(at: root + "/real-dir")
            try arranger.addFile(at: root + "/real-dir/inner.txt", contents: bytes)
            try arranger.addSymlink(at: root + "/dir-link", pointingTo: realRoot + "/real-dir")
            check(
                "a linked parent folder is resolved",
                (try? reader.realPath(of: root + "/dir-link/inner.txt")) == realRoot
                    + "/real-dir/inner.txt")
            try arranger.addSymlink(at: root + "/loop-a", pointingTo: realRoot + "/loop-b")
            try arranger.addSymlink(at: root + "/loop-b", pointingTo: realRoot + "/loop-a")
            expectFailure("a loop of links is reported", kind: "symlinkLoop") {
                _ = try reader.realPath(of: root + "/loop-a")
            }
            expectFailure("a missing path has no real path", kind: "fileNotFound") {
                _ = try reader.realPath(of: root + "/absent")
            }
            try arranger.addSymlink(
                at: root + "/escape", pointingTo: realRoot + "/../outside-target")
            check(
                "a link that leaves the root does not resolve inside the root",
                (try? reader.realPath(of: root + "/escape")).map { !$0.hasPrefix(realRoot + "/") }
                    ?? true)

            // Existence
            check("an existing file exists", reader.exists(at: root + "/file.txt"))
            check("a missing path does not exist", !reader.exists(at: root + "/absent"))
            try arranger.addSymlink(at: root + "/dangling", pointingTo: realRoot + "/absent")
            check("a dangling link exists as a link", reader.exists(at: root + "/dangling"))

            // Listing
            try arranger.addDirectory(at: root + "/list")
            try arranger.addFile(at: root + "/list/b", contents: bytes)
            try arranger.addFile(at: root + "/list/a", contents: bytes)
            try arranger.addDirectory(at: root + "/list/sub")
            try arranger.addFile(at: root + "/list/sub/deep", contents: bytes)
            check(
                "listing returns sorted top-level names only",
                (try? lister.topLevelNames(in: root + "/list")) == ["a", "b", "sub"])
            expectFailure("listing a file fails", kind: "fileUnreadable") {
                _ = try lister.topLevelNames(in: root + "/file.txt")
            }
            expectFailure("listing a missing folder fails", kind: "fileNotFound") {
                _ = try lister.topLevelNames(in: root + "/absent")
            }

            // Writing
            try writer.write(bytes, toPath: root + "/written")
            check(
                "a written file reads back",
                (try? reader.readRegularFile(at: realRoot + "/written", upToBytes: 20)) == bytes)
            let replacement = Data("new".utf8)
            try writer.write(replacement, toPath: root + "/written")
            check(
                "a second write replaces the file",
                (try? reader.readRegularFile(at: realRoot + "/written", upToBytes: 20))
                    == replacement)
            expectFailure("a write into a missing folder fails", kind: "fileUnwritable") {
                try writer.write(bytes, toPath: root + "/no-folder/file")
            }
            try writer.createDirectory(at: root + "/made/deeper/still")
            check(
                "nested folders are created",
                (try? lister.topLevelNames(in: root + "/made/deeper")) == ["still"])
            try writer.moveItem(at: root + "/written", to: root + "/moved")
            check("a moved file is gone from its old path", !reader.exists(at: root + "/written"))
            check(
                "a moved file reads at its new path",
                (try? reader.readRegularFile(at: realRoot + "/moved", upToBytes: 20)) == replacement
            )
            try writer.moveItem(at: root + "/moved", to: root + "/file.txt")
            check(
                "a move replaces the destination",
                (try? reader.readRegularFile(at: realRoot + "/file.txt", upToBytes: 20))
                    == replacement)
            try writer.removeItem(at: root + "/list")
            check(
                "a removed folder and its contents are gone",
                !reader.exists(at: root + "/list/sub/deep"))
            expectFailure("removing a missing path fails", kind: "fileUnwritable") {
                try writer.removeItem(at: root + "/absent")
            }
        } catch {
            problems.append("the suite could not arrange its files: \(error)")
        }
        return problems
    }
}
