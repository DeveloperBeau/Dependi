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
        let productRoot = realBuildDirectory + "/" + resources
        return productRoot + "/" + bundleName
    }
}
