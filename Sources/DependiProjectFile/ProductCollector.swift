import DependiDomain
import DependiEntities
import Foundation

/// Walks a target, its dependencies and its embedded targets, and gathers their package products.
struct ProductCollector {
    let files: any FileReading
    private var models: [String: ProjectModel] = [:]
    private var unreachable: Set<String> = []
    private var visited: Set<String> = []
    /// Every product found. A product that several targets link appears more than once.
    private(set) var found: [ProductReference] = []
    private let normalizer = PackageIdentityNormalizer()

    init(files: any FileReading) {
        self.files = files
    }

    /// Follows one target. Test targets and unknown ids are skipped.
    mutating func visit(_ model: ProjectModel, targetID: String) throws(DomainError) {
        guard visited.insert(model.path + "#" + targetID).inserted,
            let target = model.object(targetID, isa: "PBXNativeTarget"),
            !Self.isTestTarget(target)
        else { return }
        try collectProducts(of: target, in: model)
        try followDependencies(of: target, in: model)
        try followEmbeds(of: target, in: model)
    }

    private static func isTestTarget(_ target: ProjectModel.Object) -> Bool {
        guard let type = target["productType"] as? String else { return false }
        return type.hasSuffix("unit-test") || type.hasSuffix("ui-testing")
    }

    private mutating func collectProducts(of target: ProjectModel.Object, in model: ProjectModel)
        throws(DomainError)
    {
        for id in try model.strings(target, "packageProductDependencies") {
            guard let dependency = model.object(id, isa: "XCSwiftPackageProductDependency"),
                let name = dependency["productName"] as? String
            else {
                throw .fileUnreadable(
                    path: model.path, reason: "package product \(id) is not well formed")
            }
            found.append(
                ProductReference(
                    productName: name, packageName: try packageName(of: dependency, in: model)))
        }
    }

    private func packageName(of dependency: ProjectModel.Object, in model: ProjectModel)
        throws(DomainError) -> String?
    {
        guard let id = dependency["package"] as? String else { return nil }
        if model.object(id, isa: "XCLocalSwiftPackageReference") != nil { return nil }
        guard let remote = model.object(id, isa: "XCRemoteSwiftPackageReference"),
            let url = remote["repositoryURL"] as? String
        else {
            throw .fileUnreadable(
                path: model.path, reason: "package reference \(id) is not well formed")
        }
        return normalizer.identity(forLocation: url).value
    }

    private mutating func followDependencies(
        of target: ProjectModel.Object, in model: ProjectModel
    ) throws(DomainError) {
        for id in try model.strings(target, "dependencies") {
            guard let dependency = model.object(id, isa: "PBXTargetDependency") else { continue }
            if let direct = dependency["target"] as? String {
                try visit(model, targetID: direct)
            } else if let proxyID = dependency["targetProxy"] as? String,
                let proxy = model.object(proxyID, isa: "PBXContainerItemProxy"),
                let remote = proxy["remoteGlobalIDString"] as? String
            {
                let portal = proxy["containerPortal"] as? String
                if portal == nil || portal == model.projectID {
                    try visit(model, targetID: remote)
                } else if let portal, let other = externalModel(portal, from: model) {
                    try visit(other, targetID: remote)
                }
            }
        }
    }

    private mutating func followEmbeds(of target: ProjectModel.Object, in model: ProjectModel)
        throws(DomainError)
    {
        for phaseID in try model.strings(target, "buildPhases") {
            guard let phase = model.object(phaseID, isa: "PBXCopyFilesBuildPhase") else {
                continue
            }
            for fileID in try model.strings(phase, "files") {
                guard let buildFile = model.object(fileID, isa: "PBXBuildFile"),
                    let reference = buildFile["fileRef"] as? String,
                    let embedded = model.targetIDByProduct[reference]
                else { continue }
                try visit(model, targetID: embedded)
            }
        }
    }

    /// Loads the project that a file reference points to. An unreachable project gives `nil`.
    private mutating func externalModel(_ referenceID: String, from model: ProjectModel)
        -> ProjectModel?
    {
        guard let reference = model.object(referenceID, isa: "PBXFileReference"),
            let relative = reference["path"] as? String
        else { return nil }
        let projectFolder = ProjectPathMath.resolve(relative, against: model.folder)
        let projectFile = projectFolder + "/project.pbxproj"
        if let known = models[projectFile] { return known }
        if unreachable.contains(projectFile) { return nil }
        let loaded = try? ProjectFileLoader.load(projectFile: projectFile, files: files)
        if let loaded {
            models[projectFile] = loaded
            models[loaded.path] = loaded
        } else {
            unreachable.insert(projectFile)
        }
        return loaded
    }
}
