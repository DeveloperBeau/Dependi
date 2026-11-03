import Foundation

/// The result of one finished child process.
public struct ChildProcessResult: Sendable {
    /// The exit status of the process.
    public let status: Int32
    /// Everything the process wrote to standard output and standard error.
    public let output: String
}

/// Runs one child process and fails with a named error when it exceeds its time limit.
public enum ChildProcess {
    /// The error thrown when a process runs longer than its limit.
    public struct TimedOut: Error, CustomStringConvertible {
        let command: String
        public var description: String { "child process timed out: \(command)" }
    }

    /// Runs a command through `env` and waits for it, up to the time limit.
    public static func run(
        _ arguments: [String],
        workingDirectory: URL,
        timeoutSeconds: Double = 60
    ) throws -> ChildProcessResult {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("child-\(UUID().uuidString).txt")
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: outputURL) }
        let sink = try FileHandle(forWritingTo: outputURL)
        defer { try? sink.close() }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory
        process.standardOutput = sink
        process.standardError = sink
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        try process.run()
        if finished.wait(timeout: .now() + timeoutSeconds) == .timedOut {
            process.terminate()
            throw TimedOut(command: arguments.joined(separator: " "))
        }
        let text = String(decoding: try Data(contentsOf: outputURL), as: UTF8.self)
        return ChildProcessResult(status: process.terminationStatus, output: text)
    }
}
