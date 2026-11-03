/// A product in a package manifest.
public struct ManifestProduct: Equatable, Sendable {
    /// The product name.
    public let name: String
    /// The names of the targets that make up the product.
    public let targetNames: [String]

    /// Creates a manifest product.
    public init(name: String, targetNames: [String]) {
        self.name = name
        self.targetNames = targetNames
    }
}
