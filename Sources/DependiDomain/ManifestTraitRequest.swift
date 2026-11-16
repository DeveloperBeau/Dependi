/// A trait that a package asks a dependency to enable.
public struct ManifestTraitRequest: Equatable, Sendable {
    /// The name of the trait. `default` means the default traits of the dependency.
    public let name: String
    /// The traits of the requesting package. The request holds when one of them is enabled. Empty means it always holds.
    public let conditionTraits: [String]

    /// Creates a trait request.
    public init(name: String, conditionTraits: [String]) {
        self.name = name
        self.conditionTraits = conditionTraits
    }
}
