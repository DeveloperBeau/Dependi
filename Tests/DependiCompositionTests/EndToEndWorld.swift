import DependiComposition
import DependiDomain
import DependiTestSupport
import Foundation

/// A process runner that answers `xcrun --find swift` and `dump-package` from recorded JSON.
final class RecordedProcessRunner: ProcessRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [ProcessRequest] = []
    var dumps: [String: String] = [:]

    var requests: [ProcessRequest] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func run(_ request: ProcessRequest) throws(DomainError) -> ProcessOutput {
        lock.lock()
        recorded.append(request)
        let known = dumps
        lock.unlock()
        if request.executable == "/usr/bin/xcrun" {
            return ProcessOutput(
                exitStatus: 0, standardOutput: Data("/toolchain/usr/bin/swift\n".utf8),
                standardError: Data())
        }
        guard let index = request.arguments.firstIndex(of: "--package-path"),
            let name = request.arguments[index + 1].split(separator: "/").last.map(String.init),
            let json = known[name]
        else {
            throw .processFailed(
                command: request.executable, reason: "no recorded output for \(request.arguments)")
        }
        return ProcessOutput(exitStatus: 0, standardOutput: Data(json.utf8), standardError: Data())
    }
}

/// A project, its package checkouts and its build folders on disk, for the end-to-end tests.
final class EndToEndWorld {
    let root: URL
    let runner = RecordedProcessRunner()
    private(set) var workspaceDependencies: [[String: Any]] = []
    var environment: [String: String] = [:]

    var project: String { root.path + "/proj" }
    var products: String { root.path + "/products" }
    var sourcePackages: String { root.path + "/DD/App-abc/SourcePackages" }
    var bundle: String { products + "/App.app/Settings.bundle" }

    init(configuration: String? = "{}", projectFile: String = EndToEndWorld.alamofireProject) throws
    {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "e2e-\(UUID().uuidString)")
        let fileManager = FileManager.default
        for folder in [
            "proj/App.xcodeproj", "products/App.app", "DD/App-abc/Build/Products",
            "DD/App-abc/SourcePackages/checkouts", "home",
        ] {
            try fileManager.createDirectory(
                at: root.appendingPathComponent(folder), withIntermediateDirectories: true)
        }
        try projectFile.write(
            toFile: project + "/App.xcodeproj/project.pbxproj", atomically: true, encoding: .utf8)
        if let configuration {
            try configuration.write(
                toFile: project + "/.dependi.json", atomically: true, encoding: .utf8)
        }
        environment = [
            "ACTION": "install", "CONFIGURATION": "Release", "PLATFORM_NAME": "iphoneos",
            "TARGET_NAME": "App",
            "PROJECT_FILE_PATH": project + "/App.xcodeproj", "PROJECT_DIR": project,
            "BUILD_DIR": root.path + "/DD/App-abc/Build/Products", "TARGET_BUILD_DIR": products,
            "UNLOCALIZED_RESOURCES_FOLDER_PATH": "App.app", "WRAPPER_NAME": "App.app",
            "ENABLE_USER_SCRIPT_SANDBOXING": "NO", "HOME": root.path + "/home",
            "TMPDIR": root.path + "/home",
            "XCODE_PRODUCT_BUILD_VERSION": "TESTBUILD", "SDKROOT": "/sdk/iPhoneOS.sdk",
        ]
        try writeWorkspaceState()
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    // MARK: Building the world

    static let alamofireProject = """
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
        		R1 = {isa = XCRemoteSwiftPackageReference; repositoryURL = "https://github.com/Alamofire/Alamofire.git"; };
        		D1 = {isa = XCSwiftPackageProductDependency; package = R1; productName = Alamofire; };
        		T1 = {isa = PBXNativeTarget; name = App; productType = "com.apple.product-type.application"; dependencies = (); packageProductDependencies = (D1); buildPhases = (); buildConfigurationList = T1L; };
        		T1L = {isa = XCConfigurationList; buildConfigurations = (T1C); };
        		T1C = {isa = XCBuildConfiguration; buildSettings = {}; name = Release; };
        	};
        	rootObject = P0;
        }
        """

    /// Manifest JSON in the shape of `dump-package`.
    static func manifest(
        product: String, dependencies: [String] = [], declared: [String] = [],
        kinds: [(String, String, [String])] = []
    ) -> String {
        let products = ["{\"name\":\"\(product)\",\"targets\":[\"\(product)\"]}"]
        var targets = [
            "{\"name\":\"\(product)\",\"type\":\"regular\",\"dependencies\":[\(dependencies.map { "{\"product\":[\"\($0)\",\"\($0.lowercased() == "logging" ? "swift-log" : $0)\",null,null]}" }.joined(separator: ","))]}"
        ]
        for (name, type, deps) in kinds {
            targets.append(
                "{\"name\":\"\(name)\",\"type\":\"\(type)\",\"dependencies\":[\(deps.map { "{\"product\":[\"\($0)\",\"\($0)\",null,null]}" }.joined(separator: ","))]}"
            )
        }
        let declaredJSON = declared.map { "{\"sourceControl\":[{\"identity\":\"\($0)\"}]}" }.joined(
            separator: ",")
        return
            "{\"products\":[\(products.joined(separator: ","))],\"targets\":[\(targets.joined(separator: ","))],\"dependencies\":[\(declaredJSON)]}"
    }

    @discardableResult
    func addRemote(
        _ name: String, owner: String, license: String? = "license of NAME",
        manifest: String? = nil,
        revision: String = "r1"
    ) throws -> String {
        let folder = sourcePackages + "/checkouts/" + name
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        if let license {
            try license.replacingOccurrences(of: "NAME", with: name).write(
                toFile: folder + "/LICENSE", atomically: true, encoding: .utf8)
        }
        try "// manifest of \(name)".write(
            toFile: folder + "/Package.swift", atomically: true, encoding: .utf8)
        runner.dumps[name] =
            manifest ?? Self.manifest(product: name.prefix(1).uppercased() + name.dropFirst())
        workspaceDependencies.append([
            "basedOn": NSNull(),
            "packageRef": [
                "identity": name, "kind": "remoteSourceControl",
                "location": "https://github.com/\(owner)/\(name).git", "name": name,
            ],
            "state": [
                "checkoutState": ["revision": revision, "version": "1.0.0"],
                "name": "sourceControlCheckout",
            ],
            "subpath": name,
        ])
        try writeWorkspaceState()
        return folder
    }

    func removeRemote(_ name: String) throws {
        workspaceDependencies.removeAll { ($0["subpath"] as? String) == name }
        try writeWorkspaceState()
    }

    func writeWorkspaceState() throws {
        let object: [String: Any] = [
            "version": 7,
            "object": ["artifacts": [], "dependencies": workspaceDependencies, "prebuilts": []],
        ]
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        try data.write(to: URL(fileURLWithPath: sourcePackages + "/workspace-state.json"))
    }

    func addLocal(_ name: String, license: String = "local license", manifest: String) throws {
        let folder = project + "/Packages/" + name
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        try license.write(toFile: folder + "/LICENSE", atomically: true, encoding: .utf8)
        try "// manifest".write(
            toFile: folder + "/Package.swift", atomically: true, encoding: .utf8)
        runner.dumps[name] = manifest
    }

    // MARK: Running

    struct Result {
        let code: Int32
        let output: String
        let errors: String
    }

    func run(_ arguments: [String] = ["generate"]) throws -> Result {
        let out = root.appendingPathComponent("stdout.txt")
        let err = root.appendingPathComponent("stderr.txt")
        FileManager.default.createFile(atPath: out.path, contents: nil)
        FileManager.default.createFile(atPath: err.path, contents: nil)
        let outHandle = try FileHandle(forWritingTo: out)
        let errHandle = try FileHandle(forWritingTo: err)
        let nullInput = try requireValue(FileHandle(forReadingAtPath: "/dev/null"))
        let application = DependiApplication(
            process: runner, input: nullInput, output: outHandle, error: errHandle)
        let code = application.run(arguments: arguments, environment: environment)
        try outHandle.close()
        try errHandle.close()
        return Result(
            code: code, output: try String(contentsOf: out, encoding: .utf8),
            errors: try String(contentsOf: err, encoding: .utf8))
    }

    // MARK: Reading the output

    func plist(_ relative: String) throws -> [String: Any] {
        let data = try Data(contentsOf: URL(fileURLWithPath: bundle + "/" + relative))
        return try requireValue(
            try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }

    func files(in relative: String) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: bundle + "/" + relative)) ?? [])
            .sorted()
    }

    func indexTitles() throws -> [String] {
        let entries = try requireValue(
            try plist("Acknowledgements.plist")["PreferenceSpecifiers"] as? [[String: String]])
        return entries.compactMap { $0["Title"] }
    }
}

struct MissingValue: Error {}

/// Unwraps an optional or throws, so a failed lookup fails the test with a clear error.
func requireValue<T>(_ value: T?) throws -> T {
    guard let value else { throw MissingValue() }
    return value
}
