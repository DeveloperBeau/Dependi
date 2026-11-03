import DependiDomain
import DependiEntities
import DependiTestSupport
import Foundation
import Testing

@Suite("Configuration loader")
struct ConfigurationLoaderTests {
    private func system(configuration: String?) throws -> InMemoryFileSystem {
        let files = InMemoryFileSystem()
        try files.addDirectory(at: "/proj")
        if let configuration {
            try files.addFile(at: "/proj/.dependi.json", contents: Data(configuration.utf8))
        }
        return files
    }

    @Test("a valid file loads to the hand-written value")
    func validFileLoads() throws {
        let files = try system(
            configuration:
                #"{"excludes":["a"],"gateConfigurations":["AppStore"],"version":"1.2.3"}"#)
        let loaded = try ConfigurationLoader(files: files).load(projectDirectory: "/proj")
        #expect(loaded.excludes == ["a"])
        #expect(loaded.gateConfigurations == ["AppStore"])
        #expect(loaded.version == "1.2.3")
        #expect(loaded.includeBuildTools == false)
    }

    @Test("an absent file is a not found error that names the path")
    func absentFile() throws {
        let files = try system(configuration: nil)
        #expect(throws: DomainError.fileNotFound(path: "/proj/.dependi.json")) {
            try ConfigurationLoader(files: files).load(projectDirectory: "/proj")
        }
    }

    @Test("a file that cannot be read is passed through and is not called corrupt")
    func deniedFile() {
        struct Denied: FileReading {
            func realPath(of path: String) throws(DomainError) -> String { path }
            func readRegularFile(at realPath: String, upToBytes limit: Int) throws(DomainError)
                -> Data
            {
                throw .fileUnreadable(path: realPath, reason: "permission denied")
            }
            func exists(at path: String) -> Bool { true }
        }
        #expect(
            throws: DomainError.fileUnreadable(
                path: "/proj/.dependi.json", reason: "permission denied")
        ) {
            try ConfigurationLoader(files: Denied()).load(projectDirectory: "/proj")
        }
    }

    @Test(
        "text that is not valid configuration is corrupt",
        arguments: ["not json", "[]", "null", "", "{"])
    func corruptFile(text: String) throws {
        let files = try system(configuration: text)
        do {
            _ = try ConfigurationLoader(files: files).load(projectDirectory: "/proj")
            Issue.record("accepted: \(text)")
        } catch DomainError.configurationCorrupt(let path, _) {
            #expect(path == "/proj/.dependi.json")
        } catch {
            Issue.record("wrong error for \(text): \(error)")
        }
    }

    @Test("an unknown key is corrupt and the reason names the key")
    func unknownKeyNamed() throws {
        let files = try system(configuration: #"{"exlcudes":[]}"#)
        #expect(
            throws: DomainError.configurationCorrupt(
                path: "/proj/.dependi.json", reason: "unknown key exlcudes")
        ) {
            try ConfigurationLoader(files: files).load(projectDirectory: "/proj")
        }
    }

    @Test("a bad pinned version is corrupt and the reason names the value")
    func badVersionNamed() throws {
        let files = try system(configuration: #"{"version":"1.0;rm"}"#)
        #expect(
            throws: DomainError.configurationCorrupt(
                path: "/proj/.dependi.json", reason: "invalid version 1.0;rm")
        ) {
            try ConfigurationLoader(files: files).load(projectDirectory: "/proj")
        }
    }

    @Test("a file over one megabyte is corrupt and a folder with the name is refused")
    func oversizeAndFolder() throws {
        let big = try system(configuration: "{}" + String(repeating: " ", count: 1_048_600))
        do {
            _ = try ConfigurationLoader(files: big).load(projectDirectory: "/proj")
            Issue.record("accepted a large file")
        } catch DomainError.configurationCorrupt {
        } catch {
            Issue.record("wrong error \(error)")
        }
        let folder = InMemoryFileSystem()
        try folder.addDirectory(at: "/proj/.dependi.json")
        #expect(throws: DomainError.notRegularFile(path: "/proj/.dependi.json")) {
            try ConfigurationLoader(files: folder).load(projectDirectory: "/proj")
        }
    }
}
