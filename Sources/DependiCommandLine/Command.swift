/// A command that the command line asks Dependi to run.
public enum Command: Equatable, Sendable {
    /// Write the acknowledgements into the settings bundle.
    case generate
    /// Add Dependi to the project at the given path. A dry run changes nothing.
    case initialize(projectPath: String, isDryRun: Bool)
    /// Print the version.
    case version
    /// Print the usage text.
    case help
}
