import Foundation

/// The result of one finished child process.
struct ChildProcessResult {
    let status: Int32
    let output: String
}

/// Runs one child process and fails with a named error when it exceeds its time limit.
enum ChildProcess {
    struct TimedOut: Error, CustomStringConvertible {
        let command: String
        var description: String { "child process timed out: \(command)" }
    }

    static func run(
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
