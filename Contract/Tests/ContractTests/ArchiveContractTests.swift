import DependiComposition
import DependiDomain
import Foundation
import Testing

@Suite("A real Xcode archive", .serialized)
struct ArchiveContractTests {
    private static let project = """
        // !$*UTF8*$!
        {
        	archiveVersion = 1;
        	classes = {
        	};
        	objectVersion = 56;
        	objects = {
        		F1 = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Sources/AppMain.swift; sourceTree = "<group>"; };
        		F2 = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = App.app; sourceTree = BUILT_PRODUCTS_DIR; };
        		F3 = {isa = PBXFileReference; lastKnownFileType = "wrapper.plug-in"; path = Settings.bundle; sourceTree = "<group>"; };
        		B1 = {isa = PBXBuildFile; fileRef = F1; };
        		B3 = {isa = PBXBuildFile; fileRef = F3; };
        		B4 = {isa = PBXBuildFile; productRef = D1; };
        		G0 = {isa = PBXGroup; children = (F1, F3, G1); sourceTree = "<group>"; };
        		G1 = {isa = PBXGroup; children = (F2); name = Products; sourceTree = "<group>"; };
        		P0 = {isa = PBXProject; buildConfigurationList = PL; compatibilityVersion = "Xcode 14.0"; mainGroup = G0; productRefGroup = G1; projectDirPath = ""; projectRoot = ""; targets = (T1); packageReferences = (R1); };
        		R1 = {isa = XCLocalSwiftPackageReference; relativePath = Packages/Core; };
        		D1 = {isa = XCSwiftPackageProductDependency; productName = Core; };
        		S1 = {isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (B1); runOnlyForDeploymentPostprocessing = 0; };
        		S2 = {isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (B4); runOnlyForDeploymentPostprocessing = 0; };
        		S3 = {isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (B3); runOnlyForDeploymentPostprocessing = 0; };
        		S4 = {isa = PBXShellScriptBuildPhase; buildActionMask = 2147483647; files = (); inputFileListPaths = ("$(SRCROOT)/.dependi/inputs.xcfilelist"); name = "Dependi"; outputPaths = ("$(TARGET_BUILD_DIR)/$(UNLOCALIZED_RESOURCES_FOLDER_PATH)/Settings.bundle/Acknowledgements.plist"); runOnlyForDeploymentPostprocessing = 0; shellPath = /bin/sh; shellScript = "\\"${SRCROOT}/.dependi/run.sh\\" generate\\n"; };
        		PL = {isa = XCConfigurationList; buildConfigurations = (PC1, PC2); defaultConfigurationName = Release; };
        		PC1 = {isa = XCBuildConfiguration; buildSettings = {SDKROOT = iphoneos; IPHONEOS_DEPLOYMENT_TARGET = 17.0; SWIFT_VERSION = 5.0; }; name = Debug; };
        		PC2 = {isa = XCBuildConfiguration; buildSettings = {SDKROOT = iphoneos; IPHONEOS_DEPLOYMENT_TARGET = 17.0; SWIFT_VERSION = 5.0; }; name = Release; };
        		T1 = {isa = PBXNativeTarget; name = App; productName = App; productReference = F2; productType = "com.apple.product-type.application"; dependencies = (); packageProductDependencies = (D1); buildPhases = (S1, S2, S3, S4); buildConfigurationList = TL; };
        		TL = {isa = XCConfigurationList; buildConfigurations = (TC1, TC2); defaultConfigurationName = Release; };
        		TC1 = {isa = XCBuildConfiguration; buildSettings = {PRODUCT_BUNDLE_IDENTIFIER = example.sample.app; PRODUCT_NAME = App; GENERATE_INFOPLIST_FILE = YES; INFOPLIST_KEY_UILaunchScreen_Generation = YES; ENABLE_USER_SCRIPT_SANDBOXING = NO; CODE_SIGNING_ALLOWED = NO; }; name = Debug; };
        		TC2 = {isa = XCBuildConfiguration; buildSettings = {PRODUCT_BUNDLE_IDENTIFIER = example.sample.app; PRODUCT_NAME = App; GENERATE_INFOPLIST_FILE = YES; INFOPLIST_KEY_UILaunchScreen_Generation = YES; ENABLE_USER_SCRIPT_SANDBOXING = NO; CODE_SIGNING_ALLOWED = NO; }; name = Release; };
        	};
        	rootObject = P0;
        }
        """

    private static let scheme = """
        <?xml version="1.0" encoding="UTF-8"?>
        <Scheme LastUpgradeVersion="1500" version="1.7">
          <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES">
            <BuildActionEntries>
              <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">
                <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="T1" BuildableName="App.app" BlueprintName="App" ReferencedContainer="container:App.xcodeproj"></BuildableReference>
              </BuildActionEntry>
            </BuildActionEntries>
          </BuildAction>
          <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"></ArchiveAction>
        </Scheme>
        """

    private func makeSample() throws -> URL {
        let root = try ContractSupport.temporaryFolder("sample")
        let manager = FileManager.default
        for folder in [
            "App.xcodeproj/xcshareddata/xcschemes", "Packages/Core/Sources/Core", "Sources",
            "Settings.bundle",
        ] {
            try manager.createDirectory(
                at: root.appendingPathComponent(folder), withIntermediateDirectories: true)
        }
        func write(_ text: String, _ path: String) throws {
            try text.write(to: root.appendingPathComponent(path), atomically: true, encoding: .utf8)
        }
        try write(
            "import SwiftUI\nimport Core\n\n@main\nstruct SampleApp: App {\n    var body: some Scene { WindowGroup { Text(coreName) } }\n}\n",
            "Sources/AppMain.swift")
        try write(
            "// swift-tools-version: 6.0\nimport PackageDescription\nlet package = Package(name: \"Core\", platforms: [.iOS(.v17)], products: [.library(name: \"Core\", targets: [\"Core\"])], targets: [.target(name: \"Core\")])\n",
            "Packages/Core/Package.swift")
        try write("public let coreName = \"core\"\n", "Packages/Core/Sources/Core/Core.swift")
        try write("Core sample license text\n", "Packages/Core/LICENSE")
        try write(
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n<plist version=\"1.0\"><dict><key>StringsTable</key><string>Root</string><key>PreferenceSpecifiers</key><array><dict><key>Type</key><string>PSGroupSpecifier</string><key>Title</key><string>General</string></dict></array></dict></plist>\n",
            "Settings.bundle/Root.plist")
        try write(Self.project, "App.xcodeproj/project.pbxproj")
        try write(Self.scheme, "App.xcodeproj/xcshareddata/xcschemes/App.xcscheme")
        return root
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func install(into sample: URL) throws {
        let nullInput = try #require(FileHandle(forReadingAtPath: "/dev/null"))
        let application = DependiApplication(
            process: ContractSupport.process, input: nullInput, output: FileHandle.nullDevice,
            error: FileHandle.nullDevice,
            executablePath: repositoryRoot().appendingPathComponent("Package.swift").path,
            currentDirectory: sample.path)
        #expect(
            application.run(
                arguments: ["init", "--project", sample.path],
                environment: ContractSupport.cleanEnvironment) == 0)
        // A fresh clone or a CI machine has no installed program, so the script must build it.
        try FileManager.default.removeItem(at: sample.appendingPathComponent(".dependi/bin"))
        // The local package stands in for a third-party package in this test.
        let configURL = sample.appendingPathComponent(".dependi.json")
        var config = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: configURL)) as? [String: Any])
        config["excludes"] = []
        try JSONSerialization.data(withJSONObject: config).write(to: configURL)
    }

    private func xcodebuild(_ arguments: [String], in sample: URL, cache: URL, derived: URL) throws
        -> ProcessOutput
    {
        var environment = ProcessInfo.processInfo.environment
        environment["DEPENDI_TESTING"] = "1"
        environment["DEPENDI_REPO_URL"] = repositoryRoot().path
        environment["DEPENDI_CACHE_ROOT"] = cache.path
        return try ContractSupport.process.run(
            ProcessRequest(
                executable: "/usr/bin/xcodebuild",
                arguments: [
                    "-project", sample.appendingPathComponent("App.xcodeproj").path, "-scheme",
                    "App",
                    "-destination", "generic/platform=iOS", "-derivedDataPath", derived.path,
                    "CODE_SIGNING_ALLOWED=NO", "CODE_SIGNING_REQUIRED=NO",
                ] + arguments,
                environment: environment, workingDirectory: sample.path, timeoutSeconds: 1500,
                maximumOutputBytes: 64 * 1024 * 1024))
    }

    @Test("an archive puts the acknowledgements in the app and a Debug build puts none")
    func archiveAndDebug() throws {
        _ = try #require(ContractSupport.iosSDKPath(), "no iOS SDK installed")
        let sample = try makeSample()
        let cache = try ContractSupport.temporaryFolder("cache")
        let derived = try ContractSupport.temporaryFolder("derived")
        defer {
            for url in [sample, cache, derived] { try? FileManager.default.removeItem(at: url) }
        }
        try install(into: sample)

        let archivePath = derived.appendingPathComponent("App.xcarchive")
        let archive = try xcodebuild(
            ["archive", "-configuration", "Release", "-archivePath", archivePath.path], in: sample,
            cache: cache, derived: derived)
        let archiveLog = String(decoding: archive.standardOutput, as: UTF8.self)
        #expect(archive.exitStatus == 0, "log tail: \(archiveLog.suffix(2000))")
        #expect(archiveLog.contains("Dependi: running. archive build"))
        let bundle = archivePath.appendingPathComponent(
            "Products/Applications/App.app/Settings.bundle")
        let index = try #require(
            PropertyListSerialization.propertyList(
                from: Data(contentsOf: bundle.appendingPathComponent("Acknowledgements.plist")),
                format: nil) as? [String: Any])
        let entries = try #require(index["PreferenceSpecifiers"] as? [[String: String]])
        #expect(entries.map { $0["Title"] } == ["core"])
        let file = try #require(entries.first?["File"])
        let pane = try #require(
            PropertyListSerialization.propertyList(
                from: Data(contentsOf: bundle.appendingPathComponent(file + ".plist")), format: nil)
                as? [String: Any])
        #expect(
            (pane["PreferenceSpecifiers"] as? [[String: String]])?.first?["FooterText"]
                == "Core sample license text\n")
        let root = try #require(
            PropertyListSerialization.propertyList(
                from: Data(contentsOf: bundle.appendingPathComponent("Root.plist")), format: nil)
                as? [String: Any])
        let rootFiles = (root["PreferenceSpecifiers"] as? [[String: String]])?.compactMap {
            $0["File"]
        }
        #expect(rootFiles == ["Acknowledgements"])
        let shipped = (try? FileManager.default.contentsOfDirectory(atPath: bundle.path)) ?? []
        #expect(
            !shipped.contains { $0.hasSuffix(".bak") }, "a backup file ships in the app: \(shipped)"
        )

        let debug = try xcodebuild(
            ["build", "-configuration", "Debug"], in: sample, cache: cache, derived: derived)
        let debugLog = String(decoding: debug.standardOutput, as: UTF8.self)
        #expect(debug.exitStatus == 0, "log tail: \(debugLog.suffix(2000))")
        #expect(debugLog.contains("Dependi: skipped. configuration Debug is not in the gate list"))
        let debugBundle = derived.appendingPathComponent(
            "Build/Products/Debug-iphoneos/App.app/Settings.bundle")
        #expect(
            !FileManager.default.fileExists(
                atPath: debugBundle.appendingPathComponent("Acknowledgements.plist").path))
    }
}
