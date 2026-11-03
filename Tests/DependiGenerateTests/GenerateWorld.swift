import DependiDomain
import DependiEntities
import DependiGenerate
import DependiTestSupport
import Foundation

/// A small project, its packages and the doubles around them, for the generate tests.
final class GenerateWorld {
    static let sourcePackages = "/work/DD/App-abc/SourcePackages"
    static let archiveEnvironment: [String: String] = [
        "ACTION": "install", "CONFIGURATION": "Release", "PLATFORM_NAME": "iphoneos",
        "TARGET_NAME": "App", "PROJECT_FILE_PATH": "/proj/App.xcodeproj", "PROJECT_DIR": "/proj",
        "BUILD_DIR": "/work/DD/App-abc/Build/Products", "TARGET_BUILD_DIR": "/products",
        "UNLOCALIZED_RESOURCES_FOLDER_PATH": "App.app", "WRAPPER_NAME": "App.app",
        "ENABLE_USER_SCRIPT_SANDBOXING": "NO",
    ]

    let files = InMemoryFileSystem()
    var environment = GenerateWorld.archiveEnvironment
    var packages: [ResolvedPackage] = []
    var pinned: [PackageIdentity: String] = [:]
    var linked = LinkedProductSet(
        products: [], localPackagePaths: [], supportedPlatforms: ["iphoneos"])
    var manifests: [String: PackageManifest] = [:]
    var sourceFailure: DomainError?
    var writerFailure: DomainError?
    let console = FakeConsole(answers: [])
    private(set) var writer = RecordingAcknowledgementWriter(failure: nil)
    private(set) var manifestReader = StubManifestReader(manifests: [:])

    init(configuration: String? = "{}") throws {
        try files.addDirectory(at: "/proj")
        try files.addDirectory(at: "/products")
        if let configuration {
            try files.addFile(at: "/proj/.dependi.json", contents: Data(configuration.utf8))
        }
    }

    /// Adds a remote package with a license file and a manifest that has one product of the same name.
    @discardableResult
    func addRemote(
        _ name: String, license: String? = "MIT License", revision: String = "r1",
        product: String? = nil,
        dependencies: [ManifestDependency] = [], declared: [String] = []
    ) throws -> ResolvedPackage {
        let path = "\(Self.sourcePackages)/checkouts/\(name)"
        try files.addDirectory(at: path)
        if let license { try files.addFile(at: path + "/LICENSE", contents: Data(license.utf8)) }
        let package = ResolvedPackage(
            identity: PackageIdentity(name), kind: .remote, normalizedLocation: "org/\(name)",
            version: "1.0.0",
            revision: revision, checkoutPath: path)
        packages.append(package)
        let productName = product ?? name
        manifests[path] = PackageManifest(
            products: [ManifestProduct(name: productName, targetNames: [productName])],
            targets: [
                ManifestTarget(name: productName, kind: .regular, dependencies: dependencies)
            ],
            declaredDependencies: declared)
        return package
    }

    func link(_ productName: String, package: String?) {
        linked = LinkedProductSet(
            products: linked.products + [
                ProductReference(productName: productName, packageName: package)
            ],
            localPackagePaths: linked.localPackagePaths,
            supportedPlatforms: linked.supportedPlatforms)
    }

    func makeFeature() -> GenerateFeature {
        writer = RecordingAcknowledgementWriter(failure: writerFailure)
        manifestReader = StubManifestReader(manifests: manifests)
        let source: StubDependencySource
        if let sourceFailure {
            source = StubDependencySource(
                packages: .failure(sourceFailure), revisions: .failure(sourceFailure))
        } else {
            source = StubDependencySource(packages: .success(packages), revisions: .success(pinned))
        }
        return GenerateFeature(
            environment: FakeEnvironment(environment), files: files, directories: files,
            dependencySource: source, linkedProducts: StubLinkedProducts(.success(linked)),
            manifests: manifestReader, writer: writer, output: console)
    }

    func run() throws(DomainError) -> GenerateOutcome { try makeFeature().run() }
}
