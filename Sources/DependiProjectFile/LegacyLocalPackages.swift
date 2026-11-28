import DependiDomain

/// Finds local packages that older Xcode versions record as a folder file reference.
///
/// Such a folder holds a `Package.swift`. Its product dependencies carry no `package` key.
struct LegacyLocalPackages {
    let files: any FileReading

    /// Returns the resolved folder of every folder reference in the project that holds a manifest.
    func paths(in model: ProjectModel) -> Set<String> {
        let resolver = ReferencePathResolver(model: model)
        var result = Set<String>()
        for (id, object) in model.objects where object["isa"] as? String == "PBXFileReference" {
            guard Self.isFolder(object),
                let folder = resolver.location(of: id),
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
}
