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
            declaredDependencies: declared(root["dependencies"]),
            localDependencyPaths: localPaths(root["dependencies"], packagePath: packagePath),
            traitDefinitions: traitDefinitions(root["traits"]),
            traitRequests: traitRequests(root["dependencies"]), name: root["name"] as? String)
    }

    private static func fail(_ reason: String, _ path: String) -> DomainError {
        .processFailed(command: command, reason: "\(reason) for the package at \(path)")
    }

    private static func platforms(_ condition: Any?) -> [String] {
        guard let condition = condition as? [String: Any] else { return [] }
        return (condition["platformNames"] as? [String] ?? []).map { $0.lowercased() }
    }

    private static func traits(_ condition: Any?) -> [String] {
        guard let condition = condition as? [String: Any] else { return [] }
        return condition["traits"] as? [String] ?? []
    }

    private static func parseDependency(_ entry: [String: Any]) -> ManifestDependency? {
        if let values = entry["byName"] as? [Any], let name = values.first as? String {
            let condition = values.count > 1 ? values[1] : nil
            return ManifestDependency(
                kind: .byName, name: name, packageName: nil,
                platforms: platforms(condition), traits: traits(condition))
        }
        if let values = entry["target"] as? [Any], let name = values.first as? String {
            let condition = values.count > 1 ? values[1] : nil
            return ManifestDependency(
                kind: .target, name: name, packageName: nil,
                platforms: platforms(condition), traits: traits(condition))
        }
        if let values = entry["product"] as? [Any], let name = values.first as? String {
            let package = values.count > 1 ? values[1] as? String : nil
            let condition = values.count > 3 ? values[3] : nil
            return ManifestDependency(
                kind: .product, name: name, packageName: package,
                platforms: platforms(condition), traits: traits(condition))
        }
        return nil
    }

    private static func traitDefinitions(_ value: Any?) -> [String: [String]] {
        var definitions: [String: [String]] = [:]
        for entry in value as? [[String: Any]] ?? [] {
            guard let name = entry["name"] as? String else { continue }
            definitions[name] = entry["enabledTraits"] as? [String] ?? []
        }
        return definitions
    }

    /// The traits that the package asks of each declared dependency. A dependency that gives no `traits` list is left out.
    private static func traitRequests(_ value: Any?) -> [String: [ManifestTraitRequest]] {
        var requests: [String: [ManifestTraitRequest]] = [:]
        for entry in value as? [[String: Any]] ?? [] {
            for (_, details) in entry {
                guard let first = (details as? [[String: Any]])?.first,
                    let identity = first["identity"] as? String,
                    let raw = first["traits"] as? [[String: Any]]
                else { continue }
                requests[identity.lowercased()] = raw.compactMap { item in
                    guard let name = item["name"] as? String else { return nil }
                    return ManifestTraitRequest(
                        name: name, conditionTraits: traits(item["condition"]))
                }
            }
        }
        return requests
    }

    /// The folders of the `fileSystem` dependencies. A relative path is resolved against the package folder.
    private static func localPaths(_ value: Any?, packagePath: String) -> [String] {
        var paths: [String] = []
        for entry in value as? [[String: Any]] ?? [] {
            for details in entry["fileSystem"] as? [[String: Any]] ?? [] {
                guard let path = details["path"] as? String, !path.isEmpty else { continue }
                let absolute = path.hasPrefix("/") ? path : packagePath + "/" + path
                paths.append(URL(fileURLWithPath: absolute).standardized.path)
            }
        }
        return paths
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
