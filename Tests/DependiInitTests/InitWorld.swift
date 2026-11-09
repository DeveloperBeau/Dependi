import DependiDomain
import DependiEntities
import DependiInit
import DependiTestSupport
import Foundation

/// Records the target name it was asked about.
final class RecordingLinkedProducts: LinkedProductReading, @unchecked Sendable {
    private let box = LockedBox<[String]>([])
    let set: LinkedProductSet

    init(_ set: LinkedProductSet) {
        self.set = set
    }

    var targetsAsked: [String] { box.withValue { $0 } }

    func linkedProducts(projectFilePath: String, targetName: String) throws(DomainError)
        -> LinkedProductSet
    {
        box.withValue { $0.append(targetName) }
        return set
    }
}

/// A project folder, a running program and the doubles around them, for the init tests.
final class InitWorld {
    static let commit = String(repeating: "ab", count: 20)
    static let wrapper = "#!/bin/sh\necho wrapper\n"

    let files = InMemoryFileSystem()
    var targets = ["App"]
    var platforms = ["iphoneos"]
    var localPaths: [String] = []
    var answers: [FakeConsole.Answer] = []
    var gitResult: Result<ProcessOutput, DomainError> = .success(
        ProcessOutput(
            exitStatus: 0, standardOutput: Data((InitWorld.commit + "\n").utf8),
            standardError: Data()))
    var sourceRoot: String? = "/dependi-source"
    private(set) var console = FakeConsole(answers: [])
    private(set) var runner = FakeProcessRunner(results: [])
    private(set) var linked = RecordingLinkedProducts(
        LinkedProductSet(products: [], localPackagePaths: [], supportedPlatforms: []))

    init() throws {
        try files.addDirectory(at: "/proj/App.xcodeproj")
        try files.addDirectory(at: "/bin")
        try files.addFile(at: "/bin/dependi", contents: Data("BINARY".utf8))
    }

    func makeFeature() -> InitFeature {
        console = FakeConsole(answers: answers)
        runner = FakeProcessRunner(results: [gitResult])
        linked = RecordingLinkedProducts(
            LinkedProductSet(
                products: [], localPackagePaths: localPaths, supportedPlatforms: platforms))
        return InitFeature(
            files: files, directories: files, writer: files, executables: files,
            targets: StubApplicationTargets(.success(targets)), linkedProducts: linked,
            process: runner,
            prompts: console, output: console, executablePath: "/bin/dependi",
            sourceRoot: sourceRoot,
            wrapperText: Self.wrapper, version: "0.1.0")
    }

    func run(_ path: String = "/proj", dry: Bool = false) throws(DomainError) -> InitOutcome {
        try makeFeature().run(projectPath: path, isDryRun: dry)
    }

    func text(_ path: String) throws -> String {
        let real = try files.realPath(of: path)
        return String(
            decoding: try files.readRegularFile(at: real, upToBytes: 10_000_000), as: UTF8.self)
    }

    func data(_ path: String) throws -> Data {
        try files.readRegularFile(at: try files.realPath(of: path), upToBytes: 10_000_000)
    }

    func plist(_ path: String) throws -> [String: Any] {
        let object = try PropertyListSerialization.propertyList(
            from: try data(path), options: [], format: nil)
        guard let dictionary = object as? [String: Any] else {
            throw DomainError.initRefused(reason: "not a dictionary")
        }
        return dictionary
    }

    func specifiers(_ path: String) throws -> [[String: String]] {
        (try plist(path)["PreferenceSpecifiers"] as? [[String: String]]) ?? []
    }
}
