import DependiDomain
import DependiEntities

/// An acknowledgement writer that records what it was asked to write.
public final class RecordingAcknowledgementWriter: AcknowledgementWriting, @unchecked Sendable {
    private struct State: Sendable {
        var calls: [(acknowledgements: [Acknowledgement], bundlePath: String)] = []
    }

    private let state = LockedBox(State())
    private let failure: DomainError?

    /// Creates a writer that fails with the given error, or succeeds when it is `nil`.
    public init(failure: DomainError?) {
        self.failure = failure
    }

    /// The acknowledgements and bundle path of each call, in order.
    public var calls: [(acknowledgements: [Acknowledgement], bundlePath: String)] {
        state.withValue { $0.calls }
    }

    /// Implements `write` for `RecordingAcknowledgementWriter`.
    public func write(_ acknowledgements: [Acknowledgement], intoBundleAt bundlePath: String)
        throws(DomainError)
    {
        state.withValue { $0.calls.append((acknowledgements, bundlePath)) }
        if let failure { throw failure }
    }
}
