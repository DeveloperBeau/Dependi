/// A child process to run. The environment is explicit and never inherited.
public struct ProcessRequest: Equatable, Sendable {
    /// The absolute path of the program.
    public let executable: String
    /// The arguments, one entry for each argument.
    public let arguments: [String]
    /// The complete environment of the child.
    public let environment: [String: String]
    /// The folder to run in, or `nil` for the current folder.
    public let workingDirectory: String?
    /// The time limit in seconds.
    public let timeoutSeconds: Double
    /// The most bytes to keep from each output stream.
    public let maximumOutputBytes: Int

    /// Creates a process request.
    public init(
        executable: String,
        arguments: [String],
        environment: [String: String],
        workingDirectory: String?,
        timeoutSeconds: Double,
        maximumOutputBytes: Int
    ) {
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
        self.workingDirectory = workingDirectory
        self.timeoutSeconds = timeoutSeconds
        self.maximumOutputBytes = maximumOutputBytes
    }
}
