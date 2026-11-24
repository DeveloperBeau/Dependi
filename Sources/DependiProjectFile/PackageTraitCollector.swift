import DependiDomain
import DependiEntities
import Foundation

/// Gathers the traits that a project picks for its packages from the `traits` key of its package references.
struct PackageTraitCollector {
    private let normalizer = PackageIdentityNormalizer()
    /// The traits of every reference that lists them, joined by location.
    private var listed: [String: Set<String>] = [:]
    /// The packages that have a reference with no `traits` key.
    private var unlisted: Set<PackageIdentity> = []

    /// Adds the `traits` of one package reference at the given location.
    ///
    /// No key means the default traits. An empty list turns the defaults off. A list of names
    /// turns on exactly those names. Any other value fails, naming the reference.
    mutating func add(
        _ reference: ProjectModel.Object, id: String, location: String, in model: ProjectModel
    ) throws(DomainError) {
        guard let value = reference["traits"] else {
            unlisted.insert(normalizer.identity(forLocation: location))
            return
        }
        guard let names = value as? [String] else {
            throw .fileUnreadable(
                path: model.path,
                reason: "package reference \(id) has traits that are not a list of names")
        }
        listed[location, default: []].formUnion(names)
    }

    /// The traits that the project picks, keyed by location.
    ///
    /// A package with no listed traits has no entry, so it keeps its default traits. SwiftPM joins
    /// the traits of every reference to a package, so a package that one reference lists and another
    /// leaves unlisted also gets `default`.
    var traits: [String: Set<String>] {
        var result = listed
        for (location, names) in listed
        where unlisted.contains(normalizer.identity(forLocation: location)) {
            result[location] = names.union(["default"])
        }
        return result
    }
}
