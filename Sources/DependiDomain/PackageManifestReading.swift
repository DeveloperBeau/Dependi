/// Reads the manifest of one package.
public protocol PackageManifestReading: Sendable {
    /// Returns the products and targets of the package in a folder.
    func manifest(atPackagePath path: String) throws(DomainError) -> PackageManifest
}
