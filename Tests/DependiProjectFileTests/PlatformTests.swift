import DependiDomain
import Testing

@Suite("Supported platforms from a project file")
struct PlatformTests {
    @Test("a macOS only target returns only macosx")
    func macOSOnly() throws {
        #expect(
            try FixtureWorld.read("platform-macos", target: "MacApp").supportedPlatforms == [
                "macosx"
            ])
    }

    @Test("a Catalyst enabled iOS target also returns maccatalyst")
    func catalystEnabled() throws {
        #expect(
            try FixtureWorld.read("platform-catalyst").supportedPlatforms == [
                "iphoneos", "iphonesimulator", "maccatalyst",
            ])
    }

    @Test("Catalyst set to NO does not add maccatalyst")
    func catalystDisabled() throws {
        #expect(try FixtureWorld.read("platform-catalyst-off").supportedPlatforms == ["iphoneos"])
    }

    @Test("an SDK root of auto takes the platforms from the supported platforms setting")
    func autoSDKRoot() throws {
        #expect(
            try FixtureWorld.read("platform-auto").supportedPlatforms
                == [
                    "iphoneos", "xrsimulator", "xros",
                ].sorted())
    }

    @Test("a target without platform settings falls back to the project settings")
    func projectLevelFallback() throws {
        #expect(
            try FixtureWorld.read("platform-project-level").supportedPlatforms == [
                "iphoneos", "iphonesimulator",
            ])
    }

    @Test("a target setting wins over the project setting")
    func targetSettingWins() throws {
        #expect(
            try FixtureWorld.read("platform-macos", target: "MacApp").supportedPlatforms != [
                "iphoneos"
            ])
        #expect(
            try FixtureWorld.read("platform-catalyst-off").supportedPlatforms.contains("macosx")
                == false)
    }
}
