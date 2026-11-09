/// Whether Dependi runs in this build, and why.
public enum GateDecision: Equatable, Sendable {
    /// Dependi runs. The text says why.
    case run(reason: String)
    /// Dependi skips this build. The text says why.
    case skip(reason: String)
}
