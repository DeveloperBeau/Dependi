/// The products and targets that one package declares.
public struct PackageManifest: Equatable, Sendable {
    /// The package products.
    public let products: [ManifestProduct]
    /// The package targets.
    public let targets: [ManifestTarget]
    /// The identities of the packages that this package declares as dependencies.
    public let declaredDependencies: [String]
    /// The absolute folders of the local packages that this package declares with `.package(path:)`.
    public let localDependencyPaths: [String]

    /// Creates a package manifest.
    public init(
        products: [ManifestProduct], targets: [ManifestTarget], declaredDependencies: [String],
        localDependencyPaths: [String] = []
    ) {
        self.products = products
        self.targets = targets
        self.declaredDependencies = declaredDependencies
        self.localDependencyPaths = localDependencyPaths
    }
}
