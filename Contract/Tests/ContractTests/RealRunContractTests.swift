import DependiComposition
import DependiDomain
import DependiInit
import Foundation
import Testing

@Suite("A real run of the tool", .serialized, .timeLimit(.minutes(40)))
struct RealRunContractTests {
    private let project = """
        // !$*UTF8*$!
        {
        	archiveVersion = 1;
        	classes = {
        	};
        	objectVersion = 56;
        	objects = {
        		P0 = {isa = PBXProject; buildConfigurationList = PL; targets = (T1); packageReferences = (R1); };
        		PL = {isa = XCConfigurationList; buildConfigurations = (PC); };
        		PC = {isa = XCBuildConfiguration; buildSettings = {SDKROOT = iphoneos;}; name = Release; };
        		R1 = {isa = XCLocalSwiftPackageReference; relativePath = Packages/Core; };
        		D1 = {isa = XCSwiftPackageProductDependency; productName = Core; };
        		T1 = {isa = PBXNativeTarget; name = App; productType = "com.apple.product-type.application"; dependencies = (); packageProductDependencies = (D1); buildPhases = (); buildConfigurationList = T1L; };
        		T1L = {isa = XCConfigurationList; buildConfigurations = (T1C); };
        		T1C = {isa = XCBuildConfiguration; buildSettings = {}; name = Release; };
        	};
        	rootObject = P0;
        }
        """

    @Test("generate with the real toolchain writes the license of a local package into the bundle")
    func generateWithRealToolchain() throws {
        let root = try ContractSupport.temporaryFolder("real-run")
        defer { try? FileManager.default.removeItem(at: root) }
        let fileManager = FileManager.default
        for folder in [
            "proj/App.xcodeproj", "proj/Packages/Core/Sources/Core", "products",
            "DD/App-abc/Build/Products", "DD/App-abc/SourcePackages", "home",
        ] {
            try fileManager.createDirectory(
                at: root.appendingPathComponent(folder), withIntermediateDirectories: true)
        }
        try project.write(
            to: root.appendingPathComponent("proj/App.xcodeproj/project.pbxproj"), atomically: true,
            encoding: .utf8)
        try "{}".write(
            to: root.appendingPathComponent("proj/.dependi.json"), atomically: true, encoding: .utf8
        )
        try """
        // swift-tools-version: 6.0
        import PackageDescription
        let package = Package(name: "Core", products: [.library(name: "Core", targets: ["Core"])], targets: [.target(name: "Core")])
        """.write(
            to: root.appendingPathComponent("proj/Packages/Core/Package.swift"), atomically: true,
            encoding: .utf8)
        try "public struct Core {}\n".write(
            to: root.appendingPathComponent("proj/Packages/Core/Sources/Core/Core.swift"),
            atomically: true, encoding: .utf8)
        try "Core license text\n".write(
            to: root.appendingPathComponent("proj/Packages/Core/LICENSE"), atomically: true,
            encoding: .utf8)
        try #"{"version":7,"object":{"artifacts":[],"dependencies":[],"prebuilts":[]}}"#.write(
            to: root.appendingPathComponent("DD/App-abc/SourcePackages/workspace-state.json"),
            atomically: true, encoding: .utf8)
        try fileManager.createDirectory(
            at: root.appendingPathComponent("products/App.app"), withIntermediateDirectories: true)

        let out = root.appendingPathComponent("out.txt")
        let err = root.appendingPathComponent("err.txt")
        fileManager.createFile(atPath: out.path, contents: nil)
        fileManager.createFile(atPath: err.path, contents: nil)
        let outHandle = try FileHandle(forWritingTo: out)
        let errHandle = try FileHandle(forWritingTo: err)
        let nullInput = try #require(FileHandle(forReadingAtPath: "/dev/null"))
        let application = DependiApplication(
            process: ContractSupport.process, input: nullInput, output: outHandle, error: errHandle,
            executablePath: root.path + "/dependi", currentDirectory: root.path)
        var environment = ContractSupport.cleanEnvironment
        environment["HOME"] = root.appendingPathComponent("home").path
        environment["SDKROOT"] = ContractSupport.iosSDKPath() ?? "/no/sdk"
        for (key, value) in [
            "ACTION": "install", "CONFIGURATION": "Release", "PLATFORM_NAME": "iphoneos",
            "TARGET_NAME": "App",
            "PROJECT_FILE_PATH": root.path + "/proj/App.xcodeproj",
            "PROJECT_DIR": root.path + "/proj",
            "BUILD_DIR": root.path + "/DD/App-abc/Build/Products",
            "TARGET_BUILD_DIR": root.path + "/products",
            "UNLOCALIZED_RESOURCES_FOLDER_PATH": "App.app", "WRAPPER_NAME": "App.app",
            "ENABLE_USER_SCRIPT_SANDBOXING": "NO",
        ] { environment[key] = value }
        let code = application.run(arguments: ["generate"], environment: environment)
        try outHandle.close()
        try errHandle.close()
        let errors = try String(contentsOf: err, encoding: .utf8)
        #expect(code == 0, "errors: \(errors)")

        let bundle = root.appendingPathComponent("products/App.app/Settings.bundle")
        let index =
            try PropertyListSerialization.propertyList(
                from: Data(contentsOf: bundle.appendingPathComponent("Acknowledgements.plist")),
                format: nil) as? [String: Any]
        let entries = try #require(index?["PreferenceSpecifiers"] as? [[String: String]])
        #expect(entries.map { $0["Title"] } == ["core"])
        let file = try #require(entries.first?["File"])
        let pane =
            try PropertyListSerialization.propertyList(
                from: Data(contentsOf: bundle.appendingPathComponent(file + ".plist")), format: nil)
            as? [String: Any]
        let groups = try #require(pane?["PreferenceSpecifiers"] as? [[String: String]])
        #expect(groups.first?["FooterText"] == "Core license text\n")
    }
}

@Suite("The wrapper with the real build", .serialized, .timeLimit(.minutes(40)))
struct WrapperContractTests {
    @Test("the wrapper clones the pinned commit, builds Dependi from source and runs it")
    func wrapperBuildsFromSource() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let head = try ContractSupport.run(
            "/usr/bin/git", ["-C", repository.path, "rev-parse", "HEAD"],
            environment: ContractSupport.cleanEnvironment)
        let commit = String(decoding: head.standardOutput, as: UTF8.self).trimmingCharacters(
            in: .whitespacesAndNewlines)
        #expect(commit.count == 40, "the repository has no commit")

        let root = try ContractSupport.temporaryFolder("wrapper")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("proj/.dependi"), withIntermediateDirectories: true)
        try "{\"version\":\"0.1.0\",\"commit\":\"\(commit)\"}".write(
            to: root.appendingPathComponent("proj/.dependi.json"), atomically: true, encoding: .utf8
        )
        let script = root.appendingPathComponent("proj/.dependi/run.sh")
        try WrapperScript.text.write(to: script, atomically: true, encoding: .utf8)
        var environment = ContractSupport.cleanEnvironment
        environment["DEPENDI_TESTING"] = "1"
        environment["DEPENDI_REPO_URL"] = repository.path
        environment["DEPENDI_CACHE_ROOT"] = root.appendingPathComponent("cache").path
        environment["ACTION"] = "install"
        environment["CONFIGURATION"] = "Release"
        environment["TARGET_BUILD_DIR"] = root.path
        environment["HOME"] = root.path
        if let developer = ProcessInfo.processInfo.environment["DEVELOPER_DIR"] {
            environment["DEVELOPER_DIR"] = developer
        }

        let started = Date()
        let first = try ContractSupport.process.run(
            ProcessRequest(
                executable: "/bin/sh", arguments: [script.path, "--version"],
                environment: environment,
                workingDirectory: root.path, timeoutSeconds: 1500, maximumOutputBytes: 1_048_576))
        let firstText = String(decoding: first.standardOutput, as: UTF8.self)
        #expect(
            first.exitStatus == 0, "stderr: \(String(decoding: first.standardError, as: UTF8.self))"
        )
        #expect(firstText == "dependi 0.1.0\n")
        let firstSeconds = Date().timeIntervalSince(started)

        let second = try ContractSupport.process.run(
            ProcessRequest(
                executable: "/bin/sh", arguments: [script.path, "--version"],
                environment: environment,
                workingDirectory: root.path, timeoutSeconds: 120, maximumOutputBytes: 1_048_576))
        #expect(second.exitStatus == 0)
        #expect(String(decoding: second.standardOutput, as: UTF8.self) == "dependi 0.1.0\n")
        #expect(Date().timeIntervalSince(started) - firstSeconds < 60, "the second run built again")
    }
}
