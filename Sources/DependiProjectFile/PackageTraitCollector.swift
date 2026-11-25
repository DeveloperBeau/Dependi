import DependiDomain
import DependiEntities

/// Gathers the traits that a project picks for its packages from the `traits` key of its package references.
struct PackageTraitCollector {
    /// The traits that the project picks, keyed by the location of each reference.
    ///
    /// The collector does not match references to one package. Two references to one package keep
    /// separate entries, and the resolver joins them.
    private(set) var traits: [String: Set<String>] = [:]

    /// Adds the `traits` of one package reference at the given location.
    ///
    /// No key means the default traits. An empty list turns the defaults off. A list of names
    /// turns on exactly those names. Any other value fails, naming the reference.
    mutating func add(
        _ reference: ProjectModel.Object, id: String, location: String, in model: ProjectModel
    ) throws(DomainError) {
        guard let value = reference["traits"] else {
            traits[location, default: []].insert("default")
            return
        }
        guard let names = value as? [String] else {
            throw .fileUnreadable(
                path: model.path,
                reason: "package reference \(id) has traits that are not a list of names")
        }
        traits[location, default: []].formUnion(names)
    }
}
