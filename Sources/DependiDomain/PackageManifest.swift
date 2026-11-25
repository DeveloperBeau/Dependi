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
    /// The traits of the package. Each name maps to the traits that it enables. The `default` entry holds the default traits.
    public let traitDefinitions: [String: [String]]
    /// The traits that the package requests from each declared dependency, by identity. A dependency with no entry gets its default traits.
    public let traitRequests: [String: [ManifestTraitRequest]]

    /// Creates a package manifest.
    public init(
        products: [ManifestProduct], targets: [ManifestTarget], declaredDependencies: [String],
        localDependencyPaths: [String] = [], traitDefinitions: [String: [String]] = [:],
        traitRequests: [String: [ManifestTraitRequest]] = [:]
    ) {
        self.products = products
        self.targets = targets
        self.declaredDependencies = declaredDependencies
        self.localDependencyPaths = localDependencyPaths
        self.traitDefinitions = traitDefinitions
        self.traitRequests = traitRequests
    }
}
