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
        let unique = Set(collector.found)
        // Every other target, test targets included. A broken one is ignored, because it does not ship.
        var everything = ProductCollector(files: files, includeTests: true)
        for other in targets { try? everything.visit(model, targetID: other.id) }
        return LinkedProductSet(
            products: Self.sorted(unique),
            otherProducts: Self.sorted(Set(everything.found).subtracting(unique)),
            localPackagePaths: try localPackagePaths(in: model),
            supportedPlatforms: try SupportedPlatformDeriver.platforms(of: object, in: model))
    }

    private static func sorted(_ products: Set<ProductReference>) -> [ProductReference] {
        products.sorted {
            ($0.productName, $0.packageName ?? "") < ($1.productName, $1.packageName ?? "")
        }
    }

    func fileLocation(_ path: String) -> String {
        let name = path.split(separator: "/", omittingEmptySubsequences: true).last
        return name == "project.pbxproj" ? path : path + "/project.pbxproj"
    }

    private func localPackagePaths(in model: ProjectModel) throws(DomainError) -> [String] {
        var result = Set<String>()
        for id in try model.strings(model.project, "packageReferences") {
            guard let local = model.object(id, isa: "XCLocalSwiftPackageReference") else {
                continue
            }
            guard let relative = local["relativePath"] as? String else {
                throw .fileUnreadable(
                    path: model.path, reason: "local package \(id) has no relative path")
            }
            result.insert(ProjectPathMath.resolve(relative, against: model.folder))
        }
        return result.sorted()
    }
}
