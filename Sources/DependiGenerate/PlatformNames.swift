/// Maps Xcode platform names to the platform names that package manifests use.
enum PlatformNames {
    /// Returns the manifest platform names for a build, or `nil` to follow every dependency.
    static func manifestNames(platformName: String?, supportedPlatforms: [String]) -> Set<String>? {
        guard let platformName else { return nil }
        switch platformName {
        case "iphoneos", "iphonesimulator":
            return ["ios"]
        case "xros", "xrsimulator":
            return ["visionos"]
        case "appletvos", "appletvsimulator":
            return ["tvos"]
        case "watchos", "watchsimulator":
            return ["watchos"]
        case "macosx":
            return supportedPlatforms.contains("maccatalyst") ? ["maccatalyst", "ios"] : ["macos"]
        default:
            return nil
        }
    }
}
