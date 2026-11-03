import DependiDomain
import DependiEntities
import DependiTestSupport
import Foundation
import TestHelpers
import Testing

@testable import DependiWorkspaceState

// Real files: `real-v2` comes from a Flutter benchmark app and `real-v3` from a Swift package on
// this machine. Their own version fields are 2 and 3. Version 1 is written by hand.

@Suite("Package.resolved file", .timeLimit(.minutes(1)))
struct PinnedRevisionsTests {
    private let project = "/work/App"
    private let tail = "/xcshareddata/swiftpm/Package.resolved"

    private func reader(_ fileSystem: InMemoryFileSystem) -> WorkspaceStateReader {
        WorkspaceStateReader(files: fileSystem, directories: fileSystem)
    }

    private func pins(_ fileSystem: InMemoryFileSystem) throws(DomainError) -> [PackageIdentity:
        String]
    {
        try reader(fileSystem).pinnedRevisions(projectDirectory: project)
    }

    private func tree(_ files: [String: String]) throws -> InMemoryFileSystem {
        let fileSystem = InMemoryFileSystem()
        try fileSystem.addDirectory(at: project)
        for (path, text) in files.sorted(by: { $0.key < $1.key }) {
            let full = project + "/" + path
            let parent = String(full[..<full.lastIndex(of: "/")!])
            try fileSystem.addDirectory(at: parent)
            try fileSystem.addFile(at: full, contents: Data(text.utf8))
        }
        return fileSystem
    }

    private func resolved(_ identity: String, _ location: String, _ revision: String) -> String {
        """
        {"pins":[{"identity":"\(identity)","kind":"remoteSourceControl","location":"\(location)","state":{"revision":"\(revision)"}}],"version":3}
        """
    }

    @Test("a version 1 file gives the revision keyed by the repository URL identity")
    func version1() throws {
        let text = try Support.fixture("hand-v1.Package.resolved.json")
        let fileSystem = try tree(["Package.resolved": text])
        #expect(
            try pins(fileSystem) == [
                PackageIdentity("delta"): "4444444444444444444444444444444444444444"
            ])
    }

    @Test("a real version 2 file gives both revisions")
    func version2() throws {
        let text = try Support.fixture("real-v2.Package.resolved.json")
        let fileSystem = try tree(["Package.resolved": text])
        #expect(
            try pins(fileSystem) == [
                PackageIdentity("swift-package-manager-google-mobile-ads"):
                    "8d08e4396ea955a7d2baf067c0eedfc34ca0821d",
                PackageIdentity("swift-package-manager-google-user-messaging-platform"):
                    "13b248eaa73b7826f0efb1bcf455e251d65ecb1b",
            ])
    }

    @Test("a real version 3 file gives all four revisions")
    func version3() throws {
        let text = try Support.fixture("real-v3.Package.resolved.json")
        let fileSystem = try tree(["Package.resolved": text])
        #expect(
            try pins(fileSystem) == [
                PackageIdentity("swift-argument-parser"):
                    "626b5b7b2f45e1b0b1c6f4a309296d1d21d7311b",
                PackageIdentity("swift-docc-plugin"): "647c708be89f834fa6a6d4945442793a77ddf5b6",
                PackageIdentity("swift-docc-symbolkit"): "b45d1f2ed151d057b54504d653e0da5552844e34",
                PackageIdentity("zipfoundation"): "22787ffb59de99e5dc1fbfe80b19c97a904ad48d",
            ])
    }

    @Test("no file anywhere gives an empty dictionary")
    func noFile() throws {
        let fileSystem = try tree(["App.xcodeproj/project.pbxproj": "x", "Notes.txt": "x"])
        #expect(try pins(fileSystem).isEmpty)
    }

    @Test("the key comes from the location and not from the identity field")
    func pinIdentityFromLocation() throws {
        let fileSystem = try tree([
            "Package.resolved": resolved(
                "wrong-name", "https://github.com/Owner/Real-Name.git", "aaa")
        ])
        #expect(try pins(fileSystem) == [PackageIdentity("real-name"): "aaa"])
    }

    @Test("unknown extra fields are tolerated")
    func pinUnknownFieldsTolerated() throws {
        let text =
            "{\"originHash\":\"x\",\"future\":1,\"pins\":[{\"identity\":\"a\",\"kind\":\"k\",\"location\":\"https://h/o/a\",\"extra\":[],\"state\":{\"revision\":\"r1\",\"branch\":\"main\"}}],\"version\":4}"
        let fileSystem = try tree(["Package.resolved": text])
        #expect(try pins(fileSystem) == [PackageIdentity("a"): "r1"])
    }

    // MARK: Search order

    @Test("a workspace file wins over a project file and the root file")
    func workspaceBeforeProject() throws {
        let fileSystem = try tree([
            "App.xcworkspace" + tail: resolved("a", "https://h/o/ws", "from-workspace"),
            "App.xcodeproj/project.xcworkspace" + tail: resolved(
                "a", "https://h/o/pr", "from-project"),
            "Package.resolved": resolved("a", "https://h/o/rt", "from-root"),
        ])
        #expect(try pins(fileSystem) == [PackageIdentity("ws"): "from-workspace"])
    }

    @Test("a project file wins over the root file")
    func projectBeforeRoot() throws {
        let fileSystem = try tree([
            "App.xcodeproj/project.xcworkspace" + tail: resolved(
                "a", "https://h/o/pr", "from-project"),
            "Package.resolved": resolved("a", "https://h/o/rt", "from-root"),
        ])
        #expect(try pins(fileSystem) == [PackageIdentity("pr"): "from-project"])
    }

    @Test("the root file is used when no other file exists")
    func rootFile() throws {
        let fileSystem = try tree([
            "App.xcworkspace/contents.xcworkspacedata": "x",
            "Package.resolved": resolved("a", "https://h/o/rt", "from-root"),
        ])
        #expect(try pins(fileSystem) == [PackageIdentity("rt"): "from-root"])
    }

    // MARK: Failures

    @Test("a missing revision fails and names the file and the version")
    func missingRevision() throws {
        let text =
            "{\"pins\":[{\"identity\":\"a\",\"location\":\"https://h/o/a\",\"state\":{}}],\"version\":2}"
        let fileSystem = try tree(["Package.resolved": text])
        let error = #expect(throws: DomainError.self) { try pins(fileSystem) }
        guard case .fileUnreadable(let path, let reason)? = error else {
            Issue.record("wrong error \(String(describing: error))")
            return
        }
        #expect(path == project + "/Package.resolved")
        #expect(reason.contains("version 2"))
        #expect(reason.contains("revision"))
    }

    @Test("a version 1 file with a missing repository URL names version 1")
    func version1MissingField() throws {
        let text =
            "{\"object\":{\"pins\":[{\"package\":\"A\",\"state\":{\"revision\":\"r\"}}]},\"version\":1}"
        let fileSystem = try tree(["Package.resolved": text])
        let error = #expect(throws: DomainError.self) { try pins(fileSystem) }
        guard case .fileUnreadable(_, let reason)? = error else {
            Issue.record("wrong error \(String(describing: error))")
            return
        }
        #expect(reason.contains("version 1"))
        #expect(reason.contains("repositoryURL"))
    }

    @Test("a file with no version field fails")
    func missingVersion() throws {
        let fileSystem = try tree(["Package.resolved": "{\"pins\":[]}"])
        #expect(throws: DomainError.self) { try pins(fileSystem) }
    }

    @Test("two pins with one identity fail with an identity conflict")
    func duplicateIdentity() throws {
        let one =
            "{\"identity\":\"a\",\"location\":\"https://h/o/same\",\"state\":{\"revision\":\"r1\"}}"
        let two =
            "{\"identity\":\"b\",\"location\":\"https://h/p/same\",\"state\":{\"revision\":\"r2\"}}"
        let fileSystem = try tree(["Package.resolved": "{\"pins\":[\(one),\(two)],\"version\":3}"])
        #expect(throws: DomainError.self) { try pins(fileSystem) }
    }

    @Test("a missing project folder fails with file not found")
    func missingProjectFolder() throws {
        let fileSystem = InMemoryFileSystem()
        #expect(throws: DomainError.self) { try pins(fileSystem) }
    }

    @Test("random bytes and cut files always fail with a domain error and never crash")
    func fuzzPinsNeverCrash() throws {
        var generator = SeededGenerator()
        let valid = Data(try Support.fixture("real-v3.Package.resolved.json").utf8)
        for round in 0..<300 {
            let length = Int.random(in: 0..<200, using: &generator)
            let bytes = Data((0..<length).map { _ in UInt8.random(in: 0...255, using: &generator) })
            let cut = Data(valid.prefix(Int.random(in: 0..<(valid.count - 2), using: &generator)))
            for input in [bytes, cut] {
                let fileSystem = InMemoryFileSystem()
                try fileSystem.addDirectory(at: project)
                try fileSystem.addFile(at: project + "/Package.resolved", contents: input)
                do {
                    _ = try pins(fileSystem)
                    Issue.record(
                        "round \(round) accepted bad input, seed \(SeededGenerator.defaultSeed)")
                } catch {
                    #expect(error is DomainError)
                }
            }
        }
    }
}
