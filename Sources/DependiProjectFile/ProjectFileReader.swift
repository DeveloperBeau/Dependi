import DependiDomain
import DependiEntities
import Foundation

/// Reads the package products that a target links from an Xcode project file.
public struct ProjectFileReader: LinkedProductReading {
    let files: any FileReading

    /// Creates a reader that reads project files through the given file interface.
    public init(files: any FileReading) {
        self.files = files
    }

    /// Implements `linkedProducts` for `ProjectFileReader`.
    public func linkedProducts(projectFilePath: String, targetName: String)
        throws(DomainError) -> LinkedProductSet
    {
        let model = try ProjectFileLoader.load(
            projectFile: fileLocation(projectFilePath), files: files)
        let targets = try model.nativeTargets()
        guard let target = targets.first(where: { $0.name == targetName }),
            let object = model.object(target.id, isa: "PBXNativeTarget")
        else {
            let names = targets.map(\.name).sorted().joined(separator: ", ")
            throw .fileUnreadable(
                path: model.path,
                reason: "there is no target named \(targetName). Available targets: \(names)")
        }
        var collector = ProductCollector(files: files, includeTests: false)
        try collector.visit(model, targetID: target.id)
        let ownProducts = Set(collector.found)
        // Every other target, test targets included. A broken one is ignored, because it does not ship.
        var everything = ProductCollector(files: files, includeTests: true)
        for other in targets { try? everything.visit(model, targetID: other.id) }
        var traits = PackageTraitCollector()
        var localPaths = try packageReferences(in: model, traits: &traits)
        localPaths.formUnion(LegacyLocalPackages(files: files).paths(in: model))
        // The other projects that the walk of the app loaded can pick traits for their packages too.
        for other in collector.loadedModels {
            _ = try packageReferences(in: other, traits: &traits)
        }
        return LinkedProductSet(
            products: Self.sorted(collector.found),
            otherProducts: Self.sorted(everything.found.filter { !ownProducts.contains($0) }),
            localPackagePaths: localPaths.sorted(),
            supportedPlatforms: try SupportedPlatformDeriver.platforms(of: object, in: model),
            packageTraits: traits.traits)
    }

    private static func sorted(_ products: [ProductReference]) -> [ProductReference] {
        Set(products).sorted {
            ($0.productName, $0.packageName ?? "") < ($1.productName, $1.packageName ?? "")
        }
    }

    func fileLocation(_ path: String) -> String {
        let name = path.split(separator: "/", omittingEmptySubsequences: true).last
        return name == "project.pbxproj" ? path : path + "/project.pbxproj"
    }

    /// Reads the package references of a project. It returns the local package paths and adds the
    /// traits that each reference picks, keyed by the repository URL as written or the local path.
    private func packageReferences(
        in model: ProjectModel, traits: inout PackageTraitCollector
    ) throws(DomainError) -> Set<String> {
        var paths = Set<String>()
        for id in try model.strings(model.project, "packageReferences") {
            if let local = model.object(id, isa: "XCLocalSwiftPackageReference") {
                guard let relative = local["relativePath"] as? String else {
                    throw .fileUnreadable(
                        path: model.path, reason: "local package \(id) has no relative path")
                }
                let path = ProjectPathMath.resolve(relative, against: model.folder)
                paths.insert(path)
                try traits.add(local, id: id, location: path, in: model)
            } else if let remote = model.object(id, isa: "XCRemoteSwiftPackageReference") {
                // A reference with no URL names no package. It fails only when it picks traits.
                guard let url = remote["repositoryURL"] as? String else {
                    if remote["traits"] == nil { continue }
                    throw .fileUnreadable(
                        path: model.path, reason: "package reference \(id) has traits but no URL")
                }
                try traits.add(remote, id: id, location: url, in: model)
            }
        }
        return paths
    }
}
