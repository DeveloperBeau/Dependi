/// Finds the `SourcePackages` folder from the build directory.
public struct SourcePackagesLocator: Sendable {
    /// Creates a locator.
    public init() {}

    /// Returns the folder. A configured path wins. Otherwise the folder sits next to the `Build` folder
    /// that is followed by `Products` or `Intermediates.noindex`, and the last such `Build` folder is used.
    public func locate(buildDirectory: String?, configuredPath: String?) throws(DomainError)
        -> String
    {
        if let configuredPath, !configuredPath.isEmpty { return configuredPath }
        guard let buildDirectory, buildDirectory.hasPrefix("/") else {
            throw .sourcePackagesNotFound(tried: buildDirectory ?? "(no build directory)")
        }
        let parts = buildDirectory.split(separator: "/", omittingEmptySubsequences: true).map(
            String.init)
        var anchor: Int?
        for index in parts.indices.dropLast() where parts[index] == "Build" {
            if parts[index + 1] == "Products" || parts[index + 1] == "Intermediates.noindex" {
                anchor = index
            }
        }
        guard let anchor else { throw .sourcePackagesNotFound(tried: buildDirectory) }
        return "/" + (parts[..<anchor] + ["SourcePackages"]).joined(separator: "/")
    }
}
