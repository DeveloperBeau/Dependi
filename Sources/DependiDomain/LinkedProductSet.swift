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

    /// Creates a linked product set.
    public init(
        products: [ProductReference], otherProducts: [ProductReference] = [],
        localPackagePaths: [String], supportedPlatforms: [String]
    ) {
        self.products = products
        self.otherProducts = otherProducts
        self.localPackagePaths = localPackagePaths
        self.supportedPlatforms = supportedPlatforms
    }
}
