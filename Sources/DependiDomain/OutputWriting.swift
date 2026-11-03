/// Writes messages for the user.
public protocol OutputWriting: Sendable {
    /// Writes one line to the normal output.
    func writeLine(_ text: String)

    /// Writes one line to the error output.
    func writeErrorLine(_ text: String)
}
