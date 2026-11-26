import Foundation
import TestHelpers

/// A temporary folder of its own for one runner run. The runner reads `TMPDIR`, so its worker
/// copies and command output land here, and a test never sees the folders of another run.
struct RunnerTemporaryFolder {
    let url: URL

    static func make() throws -> RunnerTemporaryFolder {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("runner-temp-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return RunnerTemporaryFolder(url: url)
    }

    /// The `TMPDIR` setting for a runner started through `env`.
    var setting: String { "TMPDIR=\(url.path)" }

    /// The environment with `TMPDIR` pointing at this folder.
    func applied(to environment: [String: String]) -> [String: String] {
        var values = environment
        values["TMPDIR"] = url.path
        return values
    }

    func remove() { try? FileManager.default.removeItem(at: url) }
}

/// Compiles the mutation runner once for the whole test run.
enum RunnerBinary {
    static let url: URL = {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("runner-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // Every test can use the binary until the process ends, so the folder goes at exit.
        atexit {
            try? FileManager.default.removeItem(at: RunnerBinary.url.deletingLastPathComponent())
        }
        let output = folder.appendingPathComponent("mutate")
        let result = try! ChildProcess.run(
            ["swiftc", "-o", output.path, "Scripts/mutate.swift"],
            workingDirectory: RepositoryRoot.url, timeoutSeconds: 300)
        precondition(result.status == 0, "the runner did not compile: \(result.output)")
        return output
    }()

    /// Runs the compiled runner against a package and a register text. A `swift` double, when
    /// given, answers every `swift` call. Without one, the runner calls the real toolchain. The
    /// runner gets the given temporary folder, or one made and removed for this call.
    static func run(
        on package: MiniPackage, double: SwiftDouble?, register: String, extra: [String] = [],
        timeoutSeconds: Double = 600, temporary: RunnerTemporaryFolder? = nil
    ) throws -> ChildProcessResult {
        try launch(
            on: package, double: double, register: register, extra: extra,
            timeoutSeconds: timeoutSeconds, temporary: temporary
        ).result
    }

    /// Runs the compiled runner and returns the register text as the run left it.
    static func runReadingRegister(
        on package: MiniPackage, double: SwiftDouble?, register: String, extra: [String] = [],
        temporary: RunnerTemporaryFolder? = nil
    ) throws -> (result: ChildProcessResult, register: String) {
        try launch(
            on: package, double: double, register: register, extra: extra, timeoutSeconds: 600,
            temporary: temporary)
    }

    private static func launch(
        on package: MiniPackage, double: SwiftDouble?, register: String, extra: [String],
        timeoutSeconds: Double, temporary: RunnerTemporaryFolder?
    ) throws -> (result: ChildProcessResult, register: String) {
        let folder = try temporary ?? RunnerTemporaryFolder.make()
        defer { if temporary == nil { folder.remove() } }
        let registerURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("register-\(UUID().uuidString).json")
        try register.write(to: registerURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: registerURL) }
        let result = try ChildProcess.run(
            [folder.setting] + setting(double) + [
                url.path, "--root", package.root.path, "--register", registerURL.path,
            ]
                + extra,
            workingDirectory: package.root, timeoutSeconds: timeoutSeconds)
        return (result, try String(contentsOf: registerURL, encoding: .utf8))
    }

    private static func setting(_ double: SwiftDouble?) -> [String] {
        double.map { [$0.pathSetting] } ?? []
    }
}

/// Builds register JSON for the mini package.
enum Register {
    static func entry(
        id: String, search: String, replace: String, test: String = "evenNumbersAreEven",
        file: String = "Sources/Mini/Mini.swift", expected: String? = nil
    ) -> String {
        let expectation = expected.map { ",\"expected\":\"\($0)\"" } ?? ""
        return """
            {"id":"\(id)","slice":"test","file":"\(file)","search":"\(search)","replace":"\(replace)","test":"\(test)"\(expectation)}
            """
    }

    /// The test time limit for a register with a looping mutant. The `swift` double answers at
    /// once, so a short limit cannot cut a test that would pass.
    static let loopTimeout = "3"

    static func list(_ entries: [String]) -> String { "[" + entries.joined(separator: ",") + "]" }

    static let killed = entry(
        id: "even-flip", search: "number % 2 == 0", replace: "number % 2 == 1")
    static let survivor = entry(id: "unused", search: "return 7", replace: "return 8")
    static let invalid = entry(id: "broken", search: "number % 2 == 0", replace: "number % 2 ==")
    static let loopingExpectingTimeout = entry(
        id: "loop", search: "value -= 1", replace: "value += 1", test: "countDownReachesZero",
        expected: "timeout")
    static let looping = entry(
        id: "loop", search: "value -= 1", replace: "value += 1", test: "countDownReachesZero")
}
