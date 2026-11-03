import DependiDomain
import DependiEntities
import DependiPackageGraph
import DependiTestSupport
import Foundation
import Testing

@testable import DependiComposition

@Suite("Lazy manifest reader")
struct LazyManifestReaderTests {
    private func output(_ text: String, status: Int32 = 0) -> Result<ProcessOutput, DomainError> {
        .success(
            ProcessOutput(
                exitStatus: status, standardOutput: Data(text.utf8), standardError: Data()))
    }

    private func configuration(process: Double = 60, run: Double = 300) -> ToolConfiguration {
        ToolConfiguration(
            excludes: [], manualEntries: [], gateConfigurations: ["Release"],
            sourcePackagesPath: nil, outputPath: nil, includeBuildTools: false,
            allowUnreached: false, processTimeoutSeconds: process, runTimeoutSeconds: run,
            version: nil, commit: nil)
    }

    private func settings(
        _ environment: [String: String], results: [Result<ProcessOutput, DomainError>],
        configuration: ToolConfiguration? = nil
    ) throws -> (PackageGraphSettings, [ProcessRequest]) {
        let runner = FakeProcessRunner(results: results)
        let value = try LazyManifestReader.settings(
            environment: environment, configuration: configuration ?? self.configuration(),
            process: runner)
        return (value, runner.requests)
    }

    // MARK: Table of environments

    @Test("an Xcode environment gives the exact settings and runs only xcrun")
    func xcodeEnvironment() throws {
        let environment = [
            "XCODE_PRODUCT_BUILD_VERSION": "16A242d", "BUILD_DIR": "/dd/App-abc/Build/Products",
            "HOME": "/Users/ci", "TMPDIR": "/var/folders/t/", "DEVELOPER_DIR": "/Apps/Xcode.app",
            "SDKROOT": "/leak", "OTHER_LDFLAGS": "-leak",
        ]
        let (value, requests) = try settings(
            environment, results: [output("/Apps/Xcode.app/usr/bin/swift\n")])
        let expected = PackageGraphSettings(
            swiftExecutable: "/Apps/Xcode.app/usr/bin/swift", toolchainVersion: "16A242d",
            childEnvironment: [
                "PATH": "/usr/bin:/bin", "TMPDIR": "/var/folders/t/", "HOME": "/Users/ci",
                "DEVELOPER_DIR": "/Apps/Xcode.app",
            ],
            scratchDirectory: "/dd/App-abc/Build/Products/dependi/scratch",
            localCacheDirectory: "/dd/App-abc/Build/Products/dependi/manifests",
            remoteCacheDirectory: "/Users/ci/Library/Caches/dependi/manifests",
            checkoutsDirectory: "/dd/App-abc/SourcePackages/checkouts",
            processTimeoutSeconds: 60, maximumOutputBytes: 67_108_864)
        #expect(value == expected)
        #expect(requests.map(\.executable) == ["/usr/bin/xcrun"])
        #expect(requests.first?.arguments == ["--find", "swift"])
    }

    @Test("without a build version the first line of swift --version is used")
    func versionFromSwift() throws {
        let (value, requests) = try settings(
            ["HOME": "/h", "TMPDIR": "/t"],
            results: [
                output("/tc/swift\n"),
                output("Apple Swift version 6.1 (swiftlang-6.1.0.1)\nTarget: arm64\n"),
            ])
        #expect(value.toolchainVersion == "Apple Swift version 6.1 (swiftlang-6.1.0.1)")
        #expect(requests.map(\.executable) == ["/usr/bin/xcrun", "/tc/swift"])
        #expect(requests.last?.arguments == ["--version"])
    }

    @Test("an empty build version counts as absent")
    func emptyBuildVersion() throws {
        let (value, requests) = try settings(
            ["XCODE_PRODUCT_BUILD_VERSION": ""],
            results: [output("/tc/swift"), output("Swift 6\n")])
        #expect(value.toolchainVersion == "Swift 6")
        #expect(requests.count == 2)
    }

    @Test("a silent swift --version gives the version unknown")
    func unknownVersion() throws {
        let (value, _) = try settings([:], results: [output("/tc/swift"), output("")])
        #expect(value.toolchainVersion == "unknown")
    }

    @Test("with no BUILD_DIR, HOME or TMPDIR the folders fall back to /tmp")
    func foldersFallBackToTmp() throws {
        let (value, _) = try settings(
            ["XCODE_PRODUCT_BUILD_VERSION": "B"], results: [output("/tc/swift")])
        #expect(value.scratchDirectory == "/tmp/dependi/scratch")
        #expect(value.localCacheDirectory == "/tmp/dependi/manifests")
        #expect(value.remoteCacheDirectory == "/tmp/Library/Caches/dependi/manifests")
        #expect(value.checkoutsDirectory == nil)
        #expect(value.childEnvironment == ["PATH": "/usr/bin:/bin", "TMPDIR": "/tmp"])
    }

    @Test("BUILD_DIR and HOME fall back to TMPDIR when they are missing")
    func foldersFallBackToTmpdir() throws {
        let (value, _) = try settings(
            ["XCODE_PRODUCT_BUILD_VERSION": "B", "TMPDIR": "/scratch"],
            results: [output("/tc/swift")])
        #expect(value.scratchDirectory == "/scratch/dependi/scratch")
        #expect(value.localCacheDirectory == "/scratch/dependi/manifests")
        #expect(value.remoteCacheDirectory == "/scratch/Library/Caches/dependi/manifests")
    }

    @Test("a build folder without Build/Products gives no checkouts folder")
    func noCheckouts() throws {
        let (value, _) = try settings(
            ["XCODE_PRODUCT_BUILD_VERSION": "B", "BUILD_DIR": "/somewhere/else"],
            results: [output("/tc/swift")])
        #expect(value.checkoutsDirectory == nil)
        #expect(value.scratchDirectory == "/somewhere/else/dependi/scratch")
    }

    // MARK: Failures

    @Test("xcrun that exits nonzero fails and names the status")
    func xcrunFails() {
        #expect(
            throws: DomainError.processFailed(command: "/usr/bin/xcrun", reason: "exit status 72")
        ) {
            try settings([:], results: [output("", status: 72)])
        }
    }

    @Test("swift --version that exits nonzero fails and names swift")
    func versionCommandFails() {
        #expect(throws: DomainError.processFailed(command: "/tc/swift", reason: "exit status 1")) {
            try settings([:], results: [output("/tc/swift"), output("", status: 1)])
        }
    }

    @Test(
        "an xcrun answer that is not an absolute path is refused",
        arguments: ["swift", "", "\n", "./swift", "relative/swift"])
    func relativeSwiftPath(answer: String) {
        #expect(
            throws: DomainError.processFailed(
                command: "/usr/bin/xcrun", reason: "it did not print the path of swift")
        ) {
            try settings(["XCODE_PRODUCT_BUILD_VERSION": "B"], results: [output(answer)])
        }
    }

    @Test("a spawn failure of xcrun passes through unchanged")
    func spawnFailure() {
        let failure = DomainError.processFailed(command: "/usr/bin/xcrun", reason: "cannot start")
        #expect(throws: failure) { try settings([:], results: [.failure(failure)]) }
    }

    // MARK: Time limits

    @Test("the process limit of the configuration reaches every child request and the settings")
    func processLimitIsUsed() throws {
        let (value, requests) = try settings(
            [:], results: [output("/tc/swift"), output("Swift 6\n")],
            configuration: configuration(process: 12.5))
        #expect(value.processTimeoutSeconds == 12.5)
        #expect(requests.map(\.timeoutSeconds) == [12.5, 12.5])
    }

    @Test("a package read uses the configured limit for dump-package")
    func dumpPackageUsesTheLimit() throws {
        let files = InMemoryFileSystem()
        try files.addDirectory(at: "/pkg")
        try files.addFile(at: "/pkg/Package.swift", contents: Data("// swift".utf8))
        let json = #"{"name":"P","products":[],"targets":[],"dependencies":[]}"#
        let runner = FakeProcessRunner(results: [
            output("/tc/swift"), output("Swift 6\n"), output(json),
        ])
        let reader = LazyManifestReader(
            environment: ["HOME": "/h", "TMPDIR": "/t"], configuration: configuration(process: 7),
            process: runner, files: files, directories: files, writer: files)
        _ = try reader.manifest(atPackagePath: "/pkg")
        #expect(runner.requests.map(\.timeoutSeconds) == [7, 7, 7])
        #expect(runner.requests.last?.arguments.last == "dump-package")
    }

    @Test("the reader starts no process until the first manifest is needed")
    func noProcessBeforeUse() {
        let runner = FakeProcessRunner(results: [])
        let files = InMemoryFileSystem()
        _ = LazyManifestReader(
            environment: [:], configuration: configuration(), process: runner, files: files,
            directories: files, writer: files)
        #expect(runner.requests.isEmpty)
    }
}
