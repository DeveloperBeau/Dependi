/// What an init run did.
public enum InitOutcome: Equatable, Sendable {
    /// The run changed the project and installed Dependi.
    case installed
    /// A dry run reported what it would do and changed nothing.
    case reported
    /// The run stopped before changing anything, and the text says why.
    case stopped(reason: String)
}
