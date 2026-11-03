import DependiDomain

/// A process runner that returns scripted results in order and records each request.
public final class FakeProcessRunner: ProcessRunning, @unchecked Sendable {
    private struct State: Sendable {
        var results: [Result<ProcessOutput, DomainError>]
        var requests: [ProcessRequest] = []
    }

    private let state: LockedBox<State>

    /// Creates a runner that answers with the given results, one for each call.
    public init(results: [Result<ProcessOutput, DomainError>]) {
        state = LockedBox(State(results: results))
    }

    /// The requests received so far, in order.
    public var requests: [ProcessRequest] { state.withValue { $0.requests } }

    /// Implements `run` for `FakeProcessRunner`.
    public func run(_ request: ProcessRequest) throws(DomainError) -> ProcessOutput {
        let next: Result<ProcessOutput, DomainError>? = state.withValue { state in
            state.requests.append(request)
            return state.results.isEmpty ? nil : state.results.removeFirst()
        }
        guard let next else {
            throw .processFailed(command: request.executable, reason: "no scripted result left")
        }
        return try next.get()
    }
}
