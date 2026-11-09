import DependiDomain
import Foundation

/// Runs processes through another runner, and stops starting new ones when the run time is used up.
///
/// A child never gets more time than the run has left. The clock comes from outside, so tests
/// need no real time.
final class DeadlineProcessRunner: ProcessRunning {
    private let inner: any ProcessRunning
    private let limitSeconds: Double
    private let now: @Sendable () -> Double
    private let startedAt: Double

    /// Creates a runner whose run time starts now. `now` returns seconds from a steady clock.
    init(
        wrapping inner: any ProcessRunning, limitSeconds: Double,
        now: @escaping @Sendable () -> Double
    ) {
        self.inner = inner
        self.limitSeconds = limitSeconds
        self.now = now
        self.startedAt = now()
    }

    func run(_ request: ProcessRequest) throws(DomainError) -> ProcessOutput {
        let remaining = limitSeconds - (now() - startedAt)
        guard remaining > 0 else {
            throw .processFailed(
                command: ([request.executable] + request.arguments).joined(separator: " "),
                reason:
                    "the run took longer than runTimeoutSeconds (\(Self.describe(limitSeconds)) seconds), so no more processes start"
            )
        }
        let limited = ProcessRequest(
            executable: request.executable, arguments: request.arguments,
            environment: request.environment, workingDirectory: request.workingDirectory,
            timeoutSeconds: min(request.timeoutSeconds, remaining),
            maximumOutputBytes: request.maximumOutputBytes)
        return try inner.run(limited)
    }

    private static func describe(_ seconds: Double) -> String {
        seconds == seconds.rounded() ? String(Int(seconds)) : String(seconds)
    }
}
