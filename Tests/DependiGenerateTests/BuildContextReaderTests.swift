import DependiGenerate
import DependiTestSupport
import Testing

@Suite("Build context reader")
struct BuildContextReaderTests {
    @Test("every build setting is read into its own field")
    func allFieldsRead() {
        let context = BuildContextReader(
            environment: FakeEnvironment(GenerateWorld.archiveEnvironment)
        ).read()
        #expect(context.configuration == "Release")
        #expect(context.action == "install")
        #expect(context.platformName == "iphoneos")
        #expect(context.targetName == "App")
        #expect(context.projectFilePath == "/proj/App.xcodeproj")
        #expect(context.projectDirectory == "/proj")
        #expect(context.buildDirectory == "/work/DD/App-abc/Build/Products")
        #expect(context.targetBuildDirectory == "/products")
        #expect(context.unlocalizedResourcesFolderPath == "App.app")
        #expect(context.wrapperName == "App.app")
        #expect(context.isScriptSandboxEnabled == false)
    }

    @Test("a variable that is not set or is empty is nil")
    func missingAndEmptyAreNil() {
        let context = BuildContextReader(
            environment: FakeEnvironment(["ACTION": "", "TARGET_NAME": "App"])
        ).read()
        #expect(context.action == nil)
        #expect(context.configuration == nil)
        #expect(context.targetName == "App")
        #expect(context.isScriptSandboxEnabled == nil)
    }

    @Test("the sandbox setting is on only for the exact text YES")
    func sandboxValues() {
        for (text, expected) in [("YES", true), ("NO", false), ("yes", false), ("1", false)]
            as [(String, Bool)]
        {
            let context = BuildContextReader(
                environment: FakeEnvironment(["ENABLE_USER_SCRIPT_SANDBOXING": text])
            ).read()
            #expect(context.isScriptSandboxEnabled == expected, "value \(text)")
        }
    }
}
