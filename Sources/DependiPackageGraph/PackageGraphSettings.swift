/// Where and how the package graph reader runs and caches.
public struct PackageGraphSettings: Equatable, Sendable {
    /// The absolute path of the `swift` program, found once with `xcrun --find swift`.
    public let swiftExecutable: String
    /// The toolchain version. Part of the cache key.
    public let toolchainVersion: String
    /// The complete environment for `swift`. It never holds an inherited SDK setting.
    public let childEnvironment: [String: String]
    /// The folder that holds one scratch folder for each package. It is outside every package.
    public let scratchDirectory: String
    /// The cache folder for packages that are not in the checkouts folder.
    public let localCacheDirectory: String
    /// The cache folder for packages in the checkouts folder. It outlives the build folder.
    public let remoteCacheDirectory: String
    /// The checkouts folder of `SourcePackages`, or `nil` if there is none.
    public let checkoutsDirectory: String?
    /// The time limit for one `dump-package` run, in seconds.
    public let processTimeoutSeconds: Double
    /// The most bytes kept from each output stream.
    public let maximumOutputBytes: Int

    /// Creates settings.
    public init(
        swiftExecutable: String,
        toolchainVersion: String,
        childEnvironment: [String: String],
        scratchDirectory: String,
        localCacheDirectory: String,
        remoteCacheDirectory: String,
        checkoutsDirectory: String?,
        processTimeoutSeconds: Double,
        maximumOutputBytes: Int
    ) {
        self.swiftExecutable = swiftExecutable
        self.toolchainVersion = toolchainVersion
        self.childEnvironment = childEnvironment
        self.scratchDirectory = scratchDirectory
        self.localCacheDirectory = localCacheDirectory
        self.remoteCacheDirectory = remoteCacheDirectory
        self.checkoutsDirectory = checkoutsDirectory
        self.processTimeoutSeconds = processTimeoutSeconds
        self.maximumOutputBytes = maximumOutputBytes
    }
}
