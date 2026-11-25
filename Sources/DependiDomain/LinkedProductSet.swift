import DependiEntities

/// The package products that an app target links, directly or through embedded targets.
public struct LinkedProductSet: Equatable, Sendable {
    /// The linked products.
    public let products: [ProductReference]
    /// The products that the other targets of the project link, such as test targets and sibling apps.
    public let otherProducts: [ProductReference]
    /// The absolute paths of the local packages that the project references.
    public let localPackagePaths: [String]
    /// The platforms that the target supports, such as `iphoneos`.
    public let supportedPlatforms: [String]
    /// The traits that the project picks for its packages, keyed by the repository URL as written or the absolute path of a local package.
    ///
    /// A package with no entry has its default traits. An empty set turns the default traits off.
    /// A set of names turns on exactly those traits, without `default`.
    public let packageTraits: [String: Set<String>]

    /// Creates a linked product set.
    public init(
        products: [ProductReference], otherProducts: [ProductReference] = [],
        localPackagePaths: [String], supportedPlatforms: [String],
        packageTraits: [String: Set<String>] = [:]
    ) {
        self.products = products
        self.otherProducts = otherProducts
        self.localPackagePaths = localPackagePaths
        self.supportedPlatforms = supportedPlatforms
        self.packageTraits = packageTraits
    }
}
