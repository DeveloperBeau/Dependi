import DependiEntities

/// Reads the packages that a project resolved.
public protocol DependencySourceReading: Sendable {
    /// Returns the resolved remote packages with their checkout folders.
    func resolvedPackages(sourcePackagesPath: String) throws(DomainError) -> [ResolvedPackage]

    /// Returns the pinned revision of each package from the `Package.resolved` file.
    func pinnedRevisions(projectDirectory: String) throws(DomainError) -> [PackageIdentity: String]
}
