import DependiDomain
import DependiProjectFile
import DependiTestSupport
import Foundation
import Testing
import TestHelpers

@Suite("Project file failures")
struct FailureTests {
    private func reason(of error: DomainError) -> String {
        if case .fileUnreadable(_, let reason) = error { return reason }
        return "other: \(error)"
    }

    @Test("an unknown target fails and lists the available targets")
    func unknownTarget() throws {
        let (_, reader) = try FixtureWorld.single("second-target")
        do {
            _ = try reader.linkedProducts(
                projectFilePath: "/work/App/App.xcodeproj", targetName: "Nope")
            Issue.record("expected a failure")
        } catch {
            let text = reason(of: error)
            #expect(text.contains("Nope"))
            #expect(text.contains("App, OtherApp"))
        }
    }

    @Test("a missing project file fails with file not found")
    func missingFile() throws {
        let reader = ProjectFileReader(files: InMemoryFileSystem())
        #expect(throws: DomainError.fileNotFound(path: "/none/A.xcodeproj/project.pbxproj")) {
            try reader.linkedProducts(projectFilePath: "/none/A.xcodeproj", targetName: "A")
        }
    }

    @Test("a folder where the project file should be fails as not a regular file")
    func folderInsteadOfFile() throws {
        let files = InMemoryFileSystem()
        try files.addDirectory(at: "/work/A.xcodeproj/project.pbxproj")
        #expect(throws: DomainError.notRegularFile(path: "/work/A.xcodeproj/project.pbxproj")) {
            try ProjectFileReader(files: files).linkedProducts(
                projectFilePath: "/work/A.xcodeproj", targetName: "A")
        }
    }

    @Test("a project file longer than 64 MB fails and names the limit")
    func oversizeFile() throws {
        var data = FixtureWorld.fixture("direct-remote")
        data.append(Data(repeating: 0x20, count: 64 * 1024 * 1024))
        let files = InMemoryFileSystem()
        try files.addDirectory(at: "/work/A.xcodeproj")
        try files.addFile(at: "/work/A.xcodeproj/project.pbxproj", contents: data)
        do {
            _ = try ProjectFileReader(files: files).linkedProducts(
                projectFilePath: "/work/A.xcodeproj", targetName: "App")
            Issue.record("expected a failure")
        } catch {
            #expect(reason(of: error).contains("64 MB"))
        }
    }

    private func failure(of text: String) throws -> String {
        let files = InMemoryFileSystem()
        try files.addDirectory(at: "/work/A.xcodeproj")
        try files.addFile(at: "/work/A.xcodeproj/project.pbxproj", contents: Data(text.utf8))
        do {
            _ = try ProjectFileReader(files: files).linkedProducts(
                projectFilePath: "/work/A.xcodeproj", targetName: "App")
            return "no failure"
        } catch {
            return reason(of: error)
        }
    }

    @Test(
        "bad structures fail with a clear reason",
        arguments: [
            ("{ }", "objects table"),
            ("{ objects = { }; }", "root object id"),
            ("{ objects = { }; rootObject = X; }", "not a project"),
            ("( one, two )", "not a dictionary"),
            ("{ objects = { A = one; }; rootObject = A; }", "not a dictionary"),
            ("{ objects = { P = { isa = PBXNativeTarget; }; }; rootObject = P; }", "not a project"),
        ])
    func badStructures(text: String, expected: String) throws {
        let reason = try failure(of: text)
        #expect(reason.contains(expected), "got: \(reason)")
    }

    @Test("a target list that holds a non text value fails")
    func targetsNotText() throws {
        let text = """
            { objects = { P = { isa = PBXProject; targets = ( { a = b; } ); }; }; rootObject = P; }
            """
        #expect(try failure(of: text).contains("not text"))
    }

    @Test("a package product that points to a missing package fails")
    func danglingPackage() throws {
        let text = """
            { objects = {
              P = { isa = PBXProject; targets = (T); };
              T = { isa = PBXNativeTarget; name = App; packageProductDependencies = (D); };
              D = { isa = XCSwiftPackageProductDependency; productName = X; package = Gone; };
            }; rootObject = P; }
            """
        #expect(try failure(of: text).contains("package reference Gone"))
    }

    @Test("every cut of a valid file fails with file unreadable")
    func truncationAlwaysFails() throws {
        let original = FixtureWorld.fixture("embedded-framework")
        let trimmed = original.count - 2
        var random = SeededGenerator()
        for _ in 0..<150 {
            let cut = Int(random.next() % UInt64(trimmed))
            let files = InMemoryFileSystem()
            try files.addDirectory(at: "/w/A.xcodeproj")
            try files.addFile(at: "/w/A.xcodeproj/project.pbxproj", contents: original.prefix(cut))
            #expect(
                throws: DomainError.self, "cut at \(cut) with seed \(SeededGenerator.defaultSeed)"
            ) {
                try ProjectFileReader(files: files).linkedProducts(
                    projectFilePath: "/w/A.xcodeproj", targetName: "App")
            }
        }
    }

    @Test("random bytes always fail with file unreadable")
    func randomBytesFail() throws {
        var random = SeededGenerator()
        for round in 0..<150 {
            let length = Int(random.next() % 300)
            let bytes = (0..<length).map { _ in UInt8(truncatingIfNeeded: random.next()) }
            let files = InMemoryFileSystem()
            try files.addDirectory(at: "/w/A.xcodeproj")
            try files.addFile(at: "/w/A.xcodeproj/project.pbxproj", contents: Data(bytes))
            do {
                _ = try ProjectFileReader(files: files).linkedProducts(
                    projectFilePath: "/w/A.xcodeproj", targetName: "App")
                Issue.record("round \(round) seed \(SeededGenerator.defaultSeed) did not fail")
            } catch {
                guard case .fileUnreadable = error else {
                    Issue.record("round \(round): wrong error \(error)")
                    continue
                }
            }
        }
    }

    @Test("flipped bytes in a valid file give a result or file unreadable and never another error")
    func flippedBytesStayInDomain() throws {
        let original = [UInt8](FixtureWorld.fixture("app-extension"))
        var random = SeededGenerator()
        for round in 0..<300 {
            var bytes = original
            for _ in 0..<(1 + Int(random.next() % 4)) {
                bytes[Int(random.next() % UInt64(bytes.count))] = UInt8(
                    truncatingIfNeeded: random.next())
            }
            let files = InMemoryFileSystem()
            try files.addDirectory(at: "/w/A.xcodeproj")
            try files.addFile(at: "/w/A.xcodeproj/project.pbxproj", contents: Data(bytes))
            do {
                _ = try ProjectFileReader(files: files).linkedProducts(
                    projectFilePath: "/w/A.xcodeproj", targetName: "App")
            } catch {
                let isExpected: Bool
                switch error {
                case .fileUnreadable: isExpected = true
                default: isExpected = false
                }
                #expect(isExpected, "round \(round) seed \(SeededGenerator.defaultSeed): \(error)")
            }
        }
    }
}
