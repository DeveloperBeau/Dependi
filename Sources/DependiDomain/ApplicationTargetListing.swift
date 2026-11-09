/// Lists the application targets of a project.
public protocol ApplicationTargetListing: Sendable {
    /// Returns the names of the application targets in the project, sorted.
    func applicationTargets(projectFilePath: String) throws(DomainError) -> [String]
}
