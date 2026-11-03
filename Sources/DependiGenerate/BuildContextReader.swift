import DependiDomain
import DependiEntities

/// Reads the Xcode build settings from the environment.
public struct BuildContextReader: Sendable {
    private let environment: any EnvironmentReading

    /// Creates a reader that uses the given environment.
    public init(environment: any EnvironmentReading) {
        self.environment = environment
    }

    private func value(_ name: String) -> String? {
        guard let text = environment.value(for: name), !text.isEmpty else { return nil }
        return text
    }

    /// Returns the build context. A variable that is not set or is empty is `nil`.
    public func read() -> BuildContext {
        BuildContext(
            configuration: value("CONFIGURATION"), action: value("ACTION"),
            platformName: value("PLATFORM_NAME"), targetName: value("TARGET_NAME"),
            projectFilePath: value("PROJECT_FILE_PATH"), projectDirectory: value("PROJECT_DIR"),
            buildDirectory: value("BUILD_DIR"), targetBuildDirectory: value("TARGET_BUILD_DIR"),
            unlocalizedResourcesFolderPath: value("UNLOCALIZED_RESOURCES_FOLDER_PATH"),
            wrapperName: value("WRAPPER_NAME"),
            isScriptSandboxEnabled: value("ENABLE_USER_SCRIPT_SANDBOXING").map { $0 == "YES" })
    }
}
