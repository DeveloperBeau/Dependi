/// Sets up the build of one app target in a project file.
public protocol ProjectBuildConfiguring: Sendable {
    /// Adds the settings bundle, the Dependi phase and the sandbox setting to the target, and returns one line for each change.
    func configureBuild(
        projectFilePath: String, targetName: String, settingsBundlePath: String,
        backupPath: String, isDryRun: Bool
    ) throws(DomainError) -> [String]
}
