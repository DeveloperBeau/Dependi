import Foundation

/// The parts of `swift package dump-package` output that the architecture checks read.
struct PackageDump {
    /// One target of the package.
    struct Target {
        let name: String
        let type: String
        let dependencyNames: [String]
        let externalProductNames: [String]
        let upcomingFeatures: Set<String>
    }

    struct Malformed: Error, CustomStringConvertible {
        let reason: String
        var description: String { "malformed package dump: \(reason)" }
    }

    let languageVersions: [String]
    let targets: [Target]

    /// Parses the JSON that `swift package dump-package` prints.
    static func parse(_ data: Data) throws -> PackageDump {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Malformed(reason: "the top level is not an object")
        }
        guard let rawTargets = root["targets"] as? [[String: Any]] else {
            throw Malformed(reason: "targets are missing")
        }
        let versions = (root["swiftLanguageVersions"] as? [String]) ?? []
        let targets = try rawTargets.map { raw -> Target in
            guard let name = raw["name"] as? String, let type = raw["type"] as? String else {
                throw Malformed(reason: "a target has no name or type")
            }
            var names: [String] = []
            var products: [String] = []
            for dependency in (raw["dependencies"] as? [[String: [Any]]]) ?? [] {
                for (kind, values) in dependency {
                    guard let first = values.first as? String else { continue }
                    if kind == "product" { products.append(first) } else { names.append(first) }
                }
            }
            var features: Set<String> = []
            for setting in (raw["settings"] as? [[String: Any]]) ?? [] {
                let kind = setting["kind"] as? [String: Any]
                let feature = kind?["enableUpcomingFeature"] as? [String: Any]
                if let value = feature?["_0"] as? String { features.insert(value) }
            }
            return Target(
                name: name, type: type, dependencyNames: names,
                externalProductNames: products, upcomingFeatures: features)
        }
        return PackageDump(languageVersions: versions, targets: targets)
    }
}
