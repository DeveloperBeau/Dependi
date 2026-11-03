import Foundation
import TestHelpers

/// Compiles the mutation runner once for the whole test run.
enum RunnerBinary {
    static let url: URL = {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("runner-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let output = folder.appendingPathComponent("mutate")
        let result = try! ChildProcess.run(
            ["swiftc", "-o", output.path, "Scripts/mutate.swift"],
            workingDirectory: RepositoryRoot.url, timeoutSeconds: 300)
        precondition(result.status == 0, "the runner did not compile: \(result.output)")
        return output
    }()

    /// Runs the compiled runner against a package and a register text.
    static func run(
        on package: MiniPackage, register: String, extra: [String] = [],
        timeoutSeconds: Double = 600
    ) throws -> ChildProcessResult {
        let registerURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("register-\(UUID().uuidString).json")
        try register.write(to: registerURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: registerURL) }
        return try ChildProcess.run(
            [url.path, "--root", package.root.path, "--register", registerURL.path] + extra,
            workingDirectory: package.root, timeoutSeconds: timeoutSeconds)
    }
}

/// Builds register JSON for the mini package.
enum Register {
    static func entry(
        id: String, search: String, replace: String, test: String = "evenNumbersAreEven",
        file: String = "Sources/Mini/Mini.swift"
    ) -> String {
        """
        {"id":"\(id)","slice":"test","file":"\(file)","search":"\(search)","replace":"\(replace)","test":"\(test)"}
        """
    }

    static func list(_ entries: [String]) -> String { "[" + entries.joined(separator: ",") + "]" }

    static let killed = entry(
        id: "even-flip", search: "number % 2 == 0", replace: "number % 2 == 1")
    static let survivor = entry(id: "unused", search: "return 7", replace: "return 8")
    static let invalid = entry(id: "broken", search: "number % 2 == 0", replace: "number % 2 ==")
    static let looping = entry(
        id: "loop", search: "value -= 1", replace: "value += 1", test: "countDownReachesZero")
}
