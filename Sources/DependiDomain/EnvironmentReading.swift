/// Reads environment variables.
public protocol EnvironmentReading: Sendable {
    /// Returns the value of a variable, or `nil` when it is not set.
    func value(for name: String) -> String?
}
