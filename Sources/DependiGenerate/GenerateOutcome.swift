/// What a generate run did.
public enum GenerateOutcome: Equatable, Sendable {
    /// The run wrote this many acknowledgements.
    case wrote(count: Int)
    /// The run did nothing, and the text says why.
    case skipped(reason: String)
}
