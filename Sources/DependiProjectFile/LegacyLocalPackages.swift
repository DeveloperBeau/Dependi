import DependiDomain

/// Finds local packages that older Xcode versions record as a folder file reference.
///
/// Such a folder holds a `Package.swift`. Its product dependencies carry no `package` key.
struct LegacyLocalPackages {
    let files: any FileReading

    /// Returns the resolved folder of every folder reference in the project that holds a manifest.
    func paths(in model: ProjectModel) -> Set<String> {
        let parents = Self.parentGroups(in: model)
        var result = Set<String>()
        for (id, object) in model.objects where object["isa"] as? String == "PBXFileReference" {
            guard Self.isFolder(object),
                let folder = location(of: id, object, in: model, parents: parents),
                files.exists(at: folder + "/Package.swift")
            else { continue }
            result.insert(folder)
        }
        return result
    }

    private static func isFolder(_ reference: ProjectModel.Object) -> Bool {
        let kinds: Set<String> = ["wrapper", "folder"]
        let type = (reference["lastKnownFileType"] ?? reference["explicitFileType"]) as? String
        return type.map(kinds.contains) ?? false
    }

    /// Maps the id of each group member to the id of the group that lists it.
    private static func parentGroups(in model: ProjectModel) -> [String: String] {
        var parents: [String: String] = [:]
        for (id, object) in model.objects where object["isa"] as? String == "PBXGroup" {
            for child in (object["children"] as? [String]) ?? [] { parents[child] = id }
        }
        return parents
    }

    /// Resolves the folder of a reference from its source tree and its group chain.
    /// It gives `nil` for a source tree that is not inside the project, such as an SDK.
    private func location(
        of id: String, _ object: ProjectModel.Object, in model: ProjectModel,
        parents: [String: String]
    ) -> String? {
        var parts: [String] = []
        var current: (id: String, object: ProjectModel.Object)? = (id, object)
        var seen = Set<String>()
        while let node = current, seen.insert(node.id).inserted {
            let path = node.object["path"] as? String ?? ""
            let tree = node.object["sourceTree"] as? String ?? "<group>"
            if !path.isEmpty { parts.insert(path, at: 0) }
            switch tree {
            case "<absolute>":
                return ProjectPathMath.resolve(parts.joined(separator: "/"), against: "/")
            case "SOURCE_ROOT":
                return ProjectPathMath.resolve(parts.joined(separator: "/"), against: model.folder)
            case "<group>":
                guard let parent = parents[node.id], let group = model.objects[parent] else {
                    // The main group has no parent and stands for the project folder.
                    return ProjectPathMath.resolve(
                        parts.joined(separator: "/"), against: model.folder)
                }
                current = (parent, group)
            default:
                return nil
            }
        }
        return nil
    }
}
