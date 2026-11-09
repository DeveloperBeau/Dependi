/// Reads which package products a target links.
public protocol LinkedProductReading: Sendable {
    /// Returns the products linked by a target, its embedded targets and its extensions.
    func linkedProducts(projectFilePath: String, targetName: String) throws(DomainError)
        -> LinkedProductSet
}
