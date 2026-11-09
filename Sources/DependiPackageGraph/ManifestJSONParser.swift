import DependiDomain
import Foundation

/// Reads the JSON that `swift package dump-package` prints.
enum ManifestJSONParser {
    private static let command = "swift package dump-package"

    static func parse(_ data: Data, packagePath: String) throws(DomainError) -> PackageManifest {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw fail("the output is not JSON", packagePath)
        }
        guard let root = object as? [String: Any] else {
            throw fail("the output is not an object", packagePath)
        }
        guard let rawProducts = root["products"] as? [[String: Any]] else {
            throw fail("the output has no products list", packagePath)
        }
        guard let rawTargets = root["targets"] as? [[String: Any]] else {
            throw fail("the output has no targets list", packagePath)
        }
        var products: [ManifestProduct] = []
        for raw in rawProducts {
            guard let name = raw["name"] as? String else {
                throw fail("a product has no name", packagePath)
            }
            products.append(
                ManifestProduct(name: name, targetNames: raw["targets"] as? [String] ?? []))
        }
        var targets: [ManifestTarget] = []
        for raw in rawTargets {
            guard let name = raw["name"] as? String else {
                throw fail("a target has no name", packagePath)
            }
            let kind = TargetKind(rawValue: raw["type"] as? String ?? "") ?? .other
            var dependencies: [ManifestDependency] = []
            for entry in raw["dependencies"] as? [[String: Any]] ?? [] {
                if let dependency = parseDependency(entry) { dependencies.append(dependency) }
            }
            targets.append(ManifestTarget(name: name, kind: kind, dependencies: dependencies))
        }
        return PackageManifest(
            products: products, targets: targets,
            declaredDependencies: declared(root["dependencies"]))
    }

    private static func fail(_ reason: String, _ path: String) -> DomainError {
        .processFailed(command: command, reason: "\(reason) for the package at \(path)")
    }

    private static func platforms(_ condition: Any?) -> [String] {
        guard let condition = condition as? [String: Any] else { return [] }
        return (condition["platformNames"] as? [String] ?? []).map { $0.lowercased() }
    }

    private static func parseDependency(_ entry: [String: Any]) -> ManifestDependency? {
        if let values = entry["byName"] as? [Any], let name = values.first as? String {
            return ManifestDependency(
                kind: .byName, name: name, packageName: nil,
                platforms: platforms(values.count > 1 ? values[1] : nil))
        }
        if let values = entry["target"] as? [Any], let name = values.first as? String {
            return ManifestDependency(
                kind: .target, name: name, packageName: nil,
                platforms: platforms(values.count > 1 ? values[1] : nil))
        }
        if let values = entry["product"] as? [Any], let name = values.first as? String {
            let package = values.count > 1 ? values[1] as? String : nil
            return ManifestDependency(
                kind: .product, name: name, packageName: package,
                platforms: platforms(values.count > 3 ? values[3] : nil))
        }
        return nil
    }

    private static func declared(_ value: Any?) -> [String] {
        var identities: [String] = []
        for entry in value as? [[String: Any]] ?? [] {
            for (_, details) in entry {
                if let first = (details as? [[String: Any]])?.first,
                    let identity = first["identity"] as? String
                {
                    identities.append(identity.lowercased())
                }
            }
        }
        return identities
    }
}
