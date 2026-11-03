/// A package that the project resolved, with the folder that holds its files.
public struct ResolvedPackage: Hashable, Sendable, Codable {
    /// The identity of the package.
    public let identity: PackageIdentity
    /// Where the package comes from.
    public let kind: PackageKind
    /// The normalized location: lowercase, with no scheme, user, host or `.git` suffix.
    public let normalizedLocation: String
    /// The resolved version, if the package has one.
    public let version: String?
    /// The resolved commit, if the package has one.
    public let revision: String?
    /// The absolute path of the package folder.
    public let checkoutPath: String

    /// Creates a resolved package.
    public init(
        identity: PackageIdentity,
        kind: PackageKind,
        normalizedLocation: String,
        version: String?,
        revision: String?,
        checkoutPath: String
    ) {
        self.identity = identity
        self.kind = kind
        self.normalizedLocation = normalizedLocation
        self.version = version
        self.revision = revision
        self.checkoutPath = checkoutPath
    }
}
