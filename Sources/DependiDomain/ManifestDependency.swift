/// A dependency of a target in a package manifest.
public struct ManifestDependency: Equatable, Sendable {
    /// How the manifest names the dependency.
    public enum Kind: String, Equatable, Sendable {
        /// A name that is a target of the same package or a product of a dependency.
        case byName
        /// A target of the same package.
        case target
        /// A product, possibly of another package.
        case product
    }

    /// How the dependency is named.
    public let kind: Kind
    /// The target or product name.
    public let name: String
    /// The package name for a product, if the manifest gives one.
    public let packageName: String?
    /// The platforms that the dependency applies to. Empty means all.
    public let platforms: [String]

    /// Creates a manifest dependency.
    public init(kind: Kind, name: String, packageName: String?, platforms: [String]) {
        self.kind = kind
        self.name = name
        self.packageName = packageName
        self.platforms = platforms
    }
}
