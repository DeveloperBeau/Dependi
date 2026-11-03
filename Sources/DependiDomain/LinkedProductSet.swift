import DependiEntities

/// The package products that an app target links, directly or through embedded targets.
public struct LinkedProductSet: Equatable, Sendable {
    /// The linked products.
    public let products: [ProductReference]
    /// The absolute paths of the local packages that the project references.
    public let localPackagePaths: [String]
    /// The platforms that the target supports, such as `iphoneos`.
    public let supportedPlatforms: [String]

    /// Creates a linked product set.
    public init(
        products: [ProductReference], localPackagePaths: [String], supportedPlatforms: [String]
    ) {
        self.products = products
        self.localPackagePaths = localPackagePaths
        self.supportedPlatforms = supportedPlatforms
    }
}
