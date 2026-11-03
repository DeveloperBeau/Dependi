import DependiDomain

/// An environment that holds the variables given to it.
public struct FakeEnvironment: EnvironmentReading {
    private let variables: [String: String]

    /// Creates an environment from a dictionary.
    public init(_ variables: [String: String]) {
        self.variables = variables
    }

    /// Implements `value` for `FakeEnvironment`.
    public func value(for name: String) -> String? { variables[name] }
}
