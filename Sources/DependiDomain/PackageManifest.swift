/// The products and targets that one package declares.
public struct PackageManifest: Equatable, Sendable {
    /// The package products.
    public let products: [ManifestProduct]
    /// The package targets.
    public let targets: [ManifestTarget]

    /// Creates a package manifest.
    public init(products: [ManifestProduct], targets: [ManifestTarget]) {
        self.products = products
        self.targets = targets
    }
}
