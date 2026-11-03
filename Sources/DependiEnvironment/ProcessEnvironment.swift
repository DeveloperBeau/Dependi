import DependiDomain
import Foundation

/// An environment that holds a fixed set of variables. `current()` copies those of this process.
public struct ProcessEnvironment: EnvironmentReading {
    private let variables: [String: String]

    /// Creates an environment from a dictionary.
    public init(variables: [String: String]) {
        self.variables = variables
    }

    /// Returns the environment of the running process, read once at the time of the call.
    public static func current() -> ProcessEnvironment {
        ProcessEnvironment(variables: ProcessInfo.processInfo.environment)
    }

    /// Returns the value of a variable. A missing variable gives `nil`. An empty value stays empty.
    public func value(for name: String) -> String? { variables[name] }
}
