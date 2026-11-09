import DependiDomain
import DependiEntities

/// Works out where the settings bundle is inside the built product, and checks that it stays there.
struct OutputLocation {
    private let files: any FileReading

    init(files: any FileReading) {
        self.files = files
    }

    private static func isPlainRelative(_ path: String) -> Bool {
        !path.isEmpty && !path.hasPrefix("/")
            && !path.split(separator: "/", omittingEmptySubsequences: false).contains("..")
    }

    /// Returns the path of the settings bundle. It fails before any write if a setting is missing,
    /// not absolute where it must be, or if the bundle would leave the product folder.
    func bundlePath(context: BuildContext, configuration: ToolConfiguration) throws(DomainError)
        -> String
    {
        guard let targetBuildDirectory = context.targetBuildDirectory else {
            throw .buildContextIncomplete(missing: ["TARGET_BUILD_DIR"])
        }
        guard let resources = context.unlocalizedResourcesFolderPath else {
            throw .buildContextIncomplete(missing: ["UNLOCALIZED_RESOURCES_FOLDER_PATH"])
        }
        guard targetBuildDirectory.hasPrefix("/") else {
            throw .invalidOutputLocation(
                path: targetBuildDirectory, reason: "TARGET_BUILD_DIR is not absolute")
        }
        guard Self.isPlainRelative(resources) else {
            throw .invalidOutputLocation(
                path: resources,
                reason: "UNLOCALIZED_RESOURCES_FOLDER_PATH must be relative and stay in the product"
            )
        }
        let bundleName = configuration.outputPath ?? "Settings.bundle"
        guard Self.isPlainRelative(bundleName) else {
            throw .invalidOutputLocation(
                path: bundleName, reason: "the output path must be relative and stay in the product"
            )
        }
        let realBuildDirectory = try files.realPath(of: targetBuildDirectory)
        let productRoot = Self.normalized(realBuildDirectory + "/" + resources)
        let bundle = Self.normalized(productRoot + "/" + bundleName)
        try requirePlain(productRoot, name: resources)
        var walked = productRoot
        for part in bundle.dropFirst(productRoot.count).split(separator: "/") {
            walked += "/" + part
            try requirePlain(walked, name: bundleName)
        }
        return bundle
    }

    /// Refuses a path that exists but does not resolve to itself. A link, even a dangling one,
    /// would otherwise send the writes to a folder outside the product.
    private func requirePlain(_ path: String, name: String) throws(DomainError) {
        guard files.exists(at: path) else { return }
        let resolved: String
        do {
            resolved = try files.realPath(of: path)
        } catch {
            throw .invalidOutputLocation(path: name, reason: "it is a link that leads nowhere")
        }
        guard resolved == path else {
            throw .invalidOutputLocation(
                path: name, reason: "it is, or passes through, a link that leaves the product")
        }
    }

    /// Drops empty and `.` components, so that a plain path compares equal to its real path.
    private static func normalized(_ path: String) -> String {
        "/" + path.split(separator: "/").filter { $0 != "." }.joined(separator: "/")
    }
}
