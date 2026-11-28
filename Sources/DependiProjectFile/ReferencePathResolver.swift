/// Finds the folder or file that a file reference points to, from its source tree and its group chain.
struct ReferencePathResolver {
    private let model: ProjectModel
    private let parents: [String: String]

    /// Reads the group structure of the project once.
    init(model: ProjectModel) {
        self.model = model
        var parents: [String: String] = [:]
        for (id, object) in model.objects where object["isa"] as? String == "PBXGroup" {
            for child in (object["children"] as? [String]) ?? [] { parents[child] = id }
        }
        self.parents = parents
    }

    /// Resolves the path of a group member. It gives `nil` for a source tree that is not inside the
    /// project, such as an SDK, and for a group cycle.
    func location(of id: String) -> String? {
        var parts: [String] = []
        var current: (id: String, object: ProjectModel.Object)? = model.objects[id].map { (id, $0) }
        var seen = Set<String>()
        while let node = current, seen.insert(node.id).inserted {
            let path = node.object["path"] as? String ?? ""
            let tree = node.object["sourceTree"] as? String ?? "<group>"
            if !path.isEmpty { parts.insert(path, at: 0) }
            switch tree {
            case "<absolute>":
                return ProjectPathMath.standardize(parts.joined(separator: "/"))
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
