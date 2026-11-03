import DependiDomain
import DependiEntities
import DependiTestSupport
import Foundation
import Testing

@Suite("Test doubles")
struct DoubleBehaviorTests {
    private let request = ProcessRequest(
        executable: "/usr/bin/xcrun", arguments: ["swift", "--version"],
        environment: ["HOME": "/h"],
        workingDirectory: nil, timeoutSeconds: 5, maximumOutputBytes: 100)

    private func output(_ status: Int32) -> ProcessOutput {
        ProcessOutput(exitStatus: status, standardOutput: Data("out".utf8), standardError: Data())
    }

    @Test("the environment returns set values and nil for the rest")
    func environmentValues() {
        let environment = FakeEnvironment(["A": "1", "EMPTY": ""])
        #expect(environment.value(for: "A") == "1")
        #expect(environment.value(for: "EMPTY") == "")
        #expect(environment.value(for: "B") == nil)
    }

    @Test("the process runner answers in order and records every request")
    func processRunnerOrderAndRecords() throws {
        let runner = FakeProcessRunner(results: [.success(output(0)), .success(output(3))])
        #expect(try runner.run(request).exitStatus == 0)
        #expect(try runner.run(request).exitStatus == 3)
        #expect(runner.requests == [request, request])
    }

    @Test("the process runner fails with the scripted error and then when it runs out")
    func processRunnerErrors() {
        let scripted = DomainError.processFailed(command: "x", reason: "timed out")
        let runner = FakeProcessRunner(results: [.failure(scripted)])
        #expect(throws: scripted) { try runner.run(request) }
        #expect(
            throws: DomainError.processFailed(
                command: "/usr/bin/xcrun", reason: "no scripted result left")
        ) {
            try runner.run(request)
        }
        #expect(runner.requests.count == 2)
    }

    @Test("the console gives scripted answers in order and records questions and lines")
    func consoleAnswers() throws {
        let console = FakeConsole(answers: [.choice(1), .confirmation(true)])
        #expect(try console.askChoice("Which target?", options: ["A", "B"]) == 1)
        #expect(try console.askConfirmation("Delete?") == true)
        console.writeLine("hello")
        console.writeErrorLine("oops")
        #expect(console.questions == ["Which target?", "Delete?"])
        #expect(console.lines == ["hello"])
        #expect(console.errorLines == ["oops"])
    }

    @Test(
        "the console fails at the end of the input, for a wrong kind of answer and for a bad index")
    func consoleEndOfInput() {
        let empty = FakeConsole(answers: [])
        #expect(throws: DomainError.inputEnded) { try empty.askConfirmation("Sure?") }
        #expect(throws: DomainError.inputEnded) { try empty.askChoice("Pick", options: ["A"]) }
        let wrongKind = FakeConsole(answers: [.confirmation(true)])
        #expect(throws: DomainError.inputEnded) { try wrongKind.askChoice("Pick", options: ["A"]) }
        let badIndex = FakeConsole(answers: [.choice(5)])
        #expect(throws: DomainError.inputEnded) {
            try badIndex.askChoice("Pick", options: ["A", "B"])
        }
    }

    @Test("the manifest reader counts reads for each path and fails for an unknown path")
    func manifestReaderCounts() throws {
        let manifest = PackageManifest(products: [], targets: [])
        let reader = StubManifestReader(manifests: ["/p": manifest])
        _ = try reader.manifest(atPackagePath: "/p")
        _ = try reader.manifest(atPackagePath: "/p")
        #expect(reader.readCounts == ["/p": 2])
        #expect(throws: DomainError.fileUnreadable(path: "/q", reason: "no manifest scripted")) {
            try reader.manifest(atPackagePath: "/q")
        }
        #expect(reader.readCounts["/q"] == 1)
    }

    @Test("the dependency source and linked product stubs return their fixed results")
    func stubsReturnFixedResults() throws {
        let package = ResolvedPackage(
            identity: PackageIdentity("kit"), kind: .remote, normalizedLocation: "x/kit",
            version: "1.0.0",
            revision: "abc", checkoutPath: "/c/kit")
        let source = StubDependencySource(
            packages: .success([package]), revisions: .success([PackageIdentity("kit"): "abc"]))
        #expect(try source.resolvedPackages(sourcePackagesPath: "/s") == [package])
        #expect(
            try source.pinnedRevisions(projectDirectory: "/p") == [PackageIdentity("kit"): "abc"])
        let failing = StubDependencySource(
            packages: .failure(.fileUnreadable(path: "/s", reason: "gone")),
            revisions: .success([:]))
        #expect(throws: DomainError.fileUnreadable(path: "/s", reason: "gone")) {
            try failing.resolvedPackages(sourcePackagesPath: "/s")
        }
        let set = LinkedProductSet(
            products: [ProductReference(productName: "Kit", packageName: nil)],
            localPackagePaths: [],
            supportedPlatforms: ["iphoneos"])
        #expect(
            try StubLinkedProducts(.success(set)).linkedProducts(
                projectFilePath: "/a", targetName: "App") == set)
    }

    @Test("the acknowledgement writer records calls and can be told to fail")
    func writerRecords() throws {
        let acknowledgement = Acknowledgement(
            displayName: "Kit", identity: PackageIdentity("kit"), normalizedLocation: "x/kit",
            documents: [])
        let recording = RecordingAcknowledgementWriter(failure: nil)
        try recording.write([acknowledgement], intoBundleAt: "/b")
        #expect(recording.calls.count == 1)
        #expect(recording.calls.first?.bundlePath == "/b")
        let failing = RecordingAcknowledgementWriter(
            failure: .fileUnwritable(path: "/b", reason: "r"))
        #expect(throws: DomainError.fileUnwritable(path: "/b", reason: "r")) {
            try failing.write([], intoBundleAt: "/b")
        }
        #expect(failing.calls.count == 1)
    }

    @Test("a locked box stays consistent when many threads change it")
    func lockedBoxIsThreadSafe() {
        let box = LockedBox(0)
        DispatchQueue.concurrentPerform(iterations: 200) { _ in
            for _ in 0..<50 { box.withValue { $0 += 1 } }
        }
        #expect(box.withValue { $0 } == 10_000)
    }
}
