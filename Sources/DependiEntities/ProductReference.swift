/// A package product that a target links.
public struct ProductReference: Hashable, Sendable, Codable {
    /// The product name.
    public let productName: String
    /// The package name that the project file gives, or `nil` for a local package product.
    public let packageName: String?

    /// Creates a product reference.
    public init(productName: String, packageName: String?) {
        self.productName = productName
        self.packageName = packageName
    }
}
