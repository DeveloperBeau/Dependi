/// Runs child processes.
public protocol ProcessRunning: Sendable {
    /// Runs a process to the end. It fails on a spawn error, a time-out or output over the limit.
    func run(_ request: ProcessRequest) throws(DomainError) -> ProcessOutput
}
