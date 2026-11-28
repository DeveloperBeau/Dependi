/// A command that the command line asks Dependi to run.
public enum Command: Equatable, Sendable {
    /// Write the acknowledgements into the settings bundle. `forcesSinglePage` forces the single page layout for this run.
    case generate(forcesSinglePage: Bool)
    /// Add Dependi to the project at the given path. A dry run changes nothing. `editsProject` also sets up the Xcode project.
    case initialize(projectPath: String, isDryRun: Bool, editsProject: Bool)
    /// Print the version.
    case version
    /// Print the usage text.
    case help
}
