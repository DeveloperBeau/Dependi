/// Lists the entries of one folder.
public protocol DirectoryListing: Sendable {
    /// Returns the names directly inside a folder, sorted. It does not look inside subfolders.
    func topLevelNames(in directory: String) throws(DomainError) -> [String]
}
