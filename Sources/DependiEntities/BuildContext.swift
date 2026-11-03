/// The build settings that Xcode gives to a Run Script phase. A missing setting is `nil`.
public struct BuildContext: Hashable, Sendable {
    /// The build configuration name, such as `Release`.
    public let configuration: String?
    /// The build action, such as `build` or `install`. An archive uses `install`.
    public let action: String?
    /// The platform name, such as `iphoneos`.
    public let platformName: String?
    /// The name of the target that is being built.
    public let targetName: String?
    /// The path of the project file.
    public let projectFilePath: String?
    /// The folder that holds the project file.
    public let projectDirectory: String?
    /// The build products folder.
    public let buildDirectory: String?
    /// The folder that holds the built product.
    public let targetBuildDirectory: String?
    /// The path of the resources folder inside the product.
    public let unlocalizedResourcesFolderPath: String?
    /// The name of the product bundle, such as `App.app`.
    public let wrapperName: String?
    /// Whether the user script sandbox is on.
    public let isScriptSandboxEnabled: Bool?

    /// Creates a build context.
    public init(
        configuration: String?,
        action: String?,
        platformName: String?,
        targetName: String?,
        projectFilePath: String?,
        projectDirectory: String?,
        buildDirectory: String?,
        targetBuildDirectory: String?,
        unlocalizedResourcesFolderPath: String?,
        wrapperName: String?,
        isScriptSandboxEnabled: Bool?
    ) {
        self.configuration = configuration
        self.action = action
        self.platformName = platformName
        self.targetName = targetName
        self.projectFilePath = projectFilePath
        self.projectDirectory = projectDirectory
        self.buildDirectory = buildDirectory
        self.targetBuildDirectory = targetBuildDirectory
        self.unlocalizedResourcesFolderPath = unlocalizedResourcesFolderPath
        self.wrapperName = wrapperName
        self.isScriptSandboxEnabled = isScriptSandboxEnabled
    }
}
