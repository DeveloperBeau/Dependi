import Foundation
import Testing

@Suite("Forbidden content in repository files")
struct ForbiddenContentTests {
    private func makeTemporaryTree(files: [String: String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("forbidden-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for (name, text) in files {
            try text.write(to: root.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        return root
    }

    @Test("a planted user home path is found")
    func plantedUserPathIsFound() throws {
        let planted = "/Us" + "ers/someone/project"
        let root = try makeTemporaryTree(files: ["a.txt": "path \(planted)"])
        defer { try? FileManager.default.removeItem(at: root) }
        let found = try ForbiddenContentScanner.scan(root: root, relativePaths: ["a.txt"])
        #expect(found == [.init(relativePath: "a.txt", fragment: "/Us" + "ers/")])
    }

    @Test("a planted linux home path is found")
    func plantedHomePathIsFound() throws {
        let planted = "/ho" + "me/someone/project"
        let root = try makeTemporaryTree(files: ["b.txt": planted])
        defer { try? FileManager.default.removeItem(at: root) }
        let found = try ForbiddenContentScanner.scan(root: root, relativePaths: ["b.txt"])
        #expect(found == [.init(relativePath: "b.txt", fragment: "/ho" + "me/")])
    }

    @Test("a configured extra fragment is found")
    func extraFragmentIsFound() throws {
        let root = try makeTemporaryTree(files: ["c.txt": "written by Example Person"])
        defer { try? FileManager.default.removeItem(at: root) }
        let found = try ForbiddenContentScanner.scan(
            root: root, relativePaths: ["c.txt"], extraFragments: ["Example Person"])
        #expect(found == [.init(relativePath: "c.txt", fragment: "Example Person")])
    }

    @Test("words that only resemble a home path are not flagged")
    func similarWordsAreNotFlagged() throws {
        let root = try makeTemporaryTree(files: [
            "d.txt": "Users guide, the home page, a relative path like Users/name or home/name"
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        let found = try ForbiddenContentScanner.scan(root: root, relativePaths: ["d.txt"])
        #expect(found.isEmpty)
    }

    @Test("a missing file is skipped without failing the scan")
    func missingFileIsSkipped() throws {
        let root = try makeTemporaryTree(files: [:])
        defer { try? FileManager.default.removeItem(at: root) }
        let found = try ForbiddenContentScanner.scan(root: root, relativePaths: ["absent.txt"])
        #expect(found.isEmpty)
    }

    @Test("the repository holds no home path and no git user name")
    func repositoryIsClean() throws {
        let root = RepositoryRoot.url
        let files = try ForbiddenContentScanner.listCandidateFiles(root: root)
        let name = try ChildProcess.run(["git", "config", "user.name"], workingDirectory: root)
            .output.trimmingCharacters(in: .whitespacesAndNewlines)
        let extra = name.count >= 3 ? [name] : []
        let found = try ForbiddenContentScanner.scan(
            root: root, relativePaths: files, extraFragments: extra)
        #expect(found.isEmpty, "forbidden content: \(found)")
    }
}
