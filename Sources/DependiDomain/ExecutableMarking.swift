/// Marks a file so that it can be run.
public protocol ExecutableMarking: Sendable {
    /// Makes the file at the path executable by its owner and readable by everyone.
    func makeExecutable(at path: String) throws(DomainError)
}
