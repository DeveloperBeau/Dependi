/// Asks the user questions.
public protocol Prompting: Sendable {
    /// Asks the user to pick one option and returns its index. It fails at the end of the input.
    func askChoice(_ question: String, options: [String]) throws(DomainError) -> Int

    /// Asks a yes or no question. It fails at the end of the input.
    func askConfirmation(_ question: String) throws(DomainError) -> Bool
}
