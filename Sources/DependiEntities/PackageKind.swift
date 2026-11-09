/// Where a package comes from.
public enum PackageKind: String, Hashable, Sendable, Codable {
    /// A package that Xcode fetched from a repository.
    case remote
    /// A package that lives on disk next to the project.
    case local
}
