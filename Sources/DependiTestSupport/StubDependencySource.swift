import DependiDomain
import DependiEntities

/// A dependency source that returns fixed values, or a fixed error.
public struct StubDependencySource: DependencySourceReading {
    private let packages: Result<[ResolvedPackage], DomainError>
    private let revisions: Result<[PackageIdentity: String], DomainError>

    /// Creates a stub from fixed results.
    public init(
        packages: Result<[ResolvedPackage], DomainError>,
        revisions: Result<[PackageIdentity: String], DomainError>
    ) {
        self.packages = packages
        self.revisions = revisions
    }

    /// Implements `resolvedPackages` for `StubDependencySource`.
    public func resolvedPackages(sourcePackagesPath: String) throws(DomainError)
        -> [ResolvedPackage]
    {
        try packages.get()
    }

    /// Implements `pinnedRevisions` for `StubDependencySource`.
    public func pinnedRevisions(projectDirectory: String) throws(DomainError)
        -> [PackageIdentity: String]
    {
        try revisions.get()
    }
}
