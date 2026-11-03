import Foundation

/// The settings in `.dependi.json`. Decoding is strict: an unknown key fails and names the key.
public struct ToolConfiguration: Hashable, Sendable, Codable {
    /// Identities of packages to leave out.
    public let excludes: [String]
    /// Dependencies that Dependi cannot find on its own.
    public let manualEntries: [ManualEntry]
    /// Build configuration names for which Dependi runs. An archive always runs.
    public let gateConfigurations: [String]
    /// The folder that holds `SourcePackages`, if it is not found from the build directory.
    public let sourcePackagesPath: String?
    /// A path under the product root to write into, if not the Settings bundle.
    public let outputPath: String?
    /// Whether to follow the dependencies of macro and plugin targets.
    public let includeBuildTools: Bool
    /// Whether packages that no linked product reaches are allowed.
    public let allowUnreached: Bool
    /// The time limit in seconds for one child process.
    public let processTimeoutSeconds: Double
    /// The time limit in seconds for a whole run.
    public let runTimeoutSeconds: Double
    /// The pinned Dependi version, three numbers separated by dots.
    public let version: String?
    /// The pinned Dependi commit, 40 lowercase hexadecimal characters.
    public let commit: String?

    /// The gate list that applies when the key is absent.
    public static let defaultGateConfigurations = ["Release"]
    /// The default time limit for one child process.
    public static let defaultProcessTimeoutSeconds = 60.0
    /// The default time limit for a whole run.
    public static let defaultRunTimeoutSeconds = 300.0

    /// Creates a configuration.
    public init(
        excludes: [String],
        manualEntries: [ManualEntry],
        gateConfigurations: [String],
        sourcePackagesPath: String?,
        outputPath: String?,
        includeBuildTools: Bool,
        allowUnreached: Bool,
        processTimeoutSeconds: Double,
        runTimeoutSeconds: Double,
        version: String?,
        commit: String?
    ) {
        self.excludes = excludes
        self.manualEntries = manualEntries
        self.gateConfigurations = gateConfigurations
        self.sourcePackagesPath = sourcePackagesPath
        self.outputPath = outputPath
        self.includeBuildTools = includeBuildTools
        self.allowUnreached = allowUnreached
        self.processTimeoutSeconds = processTimeoutSeconds
        self.runTimeoutSeconds = runTimeoutSeconds
        self.version = version
        self.commit = commit
    }

    private struct Key: CodingKey {
        let stringValue: String
        let intValue: Int? = nil
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    private static let knownKeys: Set<String> = [
        "excludes", "manualEntries", "gateConfigurations", "sourcePackagesPath", "outputPath",
        "includeBuildTools", "allowUnreached", "processTimeoutSeconds", "runTimeoutSeconds",
        "version", "commit",
    ]

    /// Decodes a configuration. An unknown key, a bad version or a bad commit fails.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        let unknown = container.allKeys.map(\.stringValue).filter { !Self.knownKeys.contains($0) }
        if let first = unknown.sorted().first {
            throw EntityError.unknownConfigurationKey(first)
        }
        func value<T: Decodable>(_ name: String, _ type: T.Type) throws -> T? {
            try container.decodeIfPresent(type, forKey: Key(stringValue: name)!)
        }
        excludes = try value("excludes", [String].self) ?? []
        manualEntries = try value("manualEntries", [ManualEntry].self) ?? []
        gateConfigurations =
            try value("gateConfigurations", [String].self) ?? Self.defaultGateConfigurations
        sourcePackagesPath = try value("sourcePackagesPath", String.self)
        outputPath = try value("outputPath", String.self)
        includeBuildTools = try value("includeBuildTools", Bool.self) ?? false
        allowUnreached = try value("allowUnreached", Bool.self) ?? false
        processTimeoutSeconds =
            try value("processTimeoutSeconds", Double.self) ?? Self.defaultProcessTimeoutSeconds
        runTimeoutSeconds =
            try value("runTimeoutSeconds", Double.self) ?? Self.defaultRunTimeoutSeconds
        let version = try value("version", String.self)
        if let version,
            version.range(of: #"^[0-9]+\.[0-9]+\.[0-9]+$"#, options: .regularExpression) == nil
        {
            throw EntityError.invalidVersion(version)
        }
        self.version = version
        let commit = try value("commit", String.self)
        if let commit, commit.range(of: #"^[0-9a-f]{40}$"#, options: .regularExpression) == nil {
            throw EntityError.invalidCommit(commit)
        }
        self.commit = commit
    }

    /// Encodes the configuration. Optional keys that are not set are left out.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        func put<T: Encodable>(_ name: String, _ value: T?) throws {
            try container.encodeIfPresent(value, forKey: Key(stringValue: name)!)
        }
        try put("excludes", excludes)
        try put("manualEntries", manualEntries)
        try put("gateConfigurations", gateConfigurations)
        try put("sourcePackagesPath", sourcePackagesPath)
        try put("outputPath", outputPath)
        try put("includeBuildTools", includeBuildTools)
        try put("allowUnreached", allowUnreached)
        try put("processTimeoutSeconds", processTimeoutSeconds)
        try put("runTimeoutSeconds", runTimeoutSeconds)
        try put("version", version)
        try put("commit", commit)
    }
}
