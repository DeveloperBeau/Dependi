import Foundation

/// What a finished child process produced.
public struct ProcessOutput: Equatable, Sendable {
    /// The exit status.
    public let exitStatus: Int32
    /// The bytes written to standard output.
    public let standardOutput: Data
    /// The bytes written to standard error.
    public let standardError: Data

    /// Creates a process output.
    public init(exitStatus: Int32, standardOutput: Data, standardError: Data) {
        self.exitStatus = exitStatus
        self.standardOutput = standardOutput
        self.standardError = standardError
    }
}
