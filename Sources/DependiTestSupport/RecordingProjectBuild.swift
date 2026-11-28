import DependiDomain

/// A project build double that records each call and returns a fixed result.
public final class RecordingProjectBuild: ProjectBuildConfiguring, @unchecked Sendable {
    /// One recorded call.
    public struct Call: Equatable, Sendable {
        /// The project folder path that was passed.
        public let projectFilePath: String
        /// The target name that was passed.
        public let targetName: String
        /// The settings bundle path that was passed.
        public let settingsBundlePath: String
        /// The backup path that was passed.
        public let backupPath: String
        /// Whether the call was a dry run.
        public let isDryRun: Bool

        /// Creates a call record from the five values of a call.
        public init(
            projectFilePath: String, targetName: String, settingsBundlePath: String,
            backupPath: String, isDryRun: Bool
        ) {
            self.projectFilePath = projectFilePath
            self.targetName = targetName
            self.settingsBundlePath = settingsBundlePath
            self.backupPath = backupPath
            self.isDryRun = isDryRun
        }
    }

    private let box = LockedBox<[Call]>([])
    private let result: Result<[String], DomainError>

    /// Creates a double that returns `result` for every call.
    public init(_ result: Result<[String], DomainError>) {
        self.result = result
    }

    /// Every call so far, in order.
    public var calls: [Call] { box.withValue { $0 } }

    /// Implements `configureBuild` for `RecordingProjectBuild`.
    public func configureBuild(
        projectFilePath: String, targetName: String, settingsBundlePath: String,
        backupPath: String, isDryRun: Bool
    ) throws(DomainError) -> [String] {
        box.withValue {
            $0.append(
                Call(
                    projectFilePath: projectFilePath, targetName: targetName,
                    settingsBundlePath: settingsBundlePath, backupPath: backupPath,
                    isDryRun: isDryRun))
        }
        return try result.get()
    }
}
