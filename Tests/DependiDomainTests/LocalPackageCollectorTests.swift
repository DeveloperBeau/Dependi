import DependiDomain
import DependiEntities
import DependiTestSupport
import Testing

@Suite("Local package collector", .timeLimit(.minutes(1)))
struct LocalPackageCollectorTests {
    private let files = InMemoryFileSystem()

    private func local(_ path: String) -> ResolvedPackage {
        let normalizer = PackageIdentityNormalizer()
        return ResolvedPackage(
            identity: normalizer.identity(forLocation: path), kind: .local,
            normalizedLocation: normalizer.normalizedLocation(of: path), version: nil,
            revision: nil, checkoutPath: path)
    }

    private func manifest(_ paths: [String]) -> PackageManifest {
        PackageManifest(
            products: [], targets: [], declaredDependencies: [], localDependencyPaths: paths)
    }

    private func collect(
        _ start: [String], manifests: [String: PackageManifest]
    ) throws(DomainError) -> [String] {
        try LocalPackageCollector(
            manifests: StubManifestReader(manifests: manifests), files: files,
            normalizer: PackageIdentityNormalizer()
        ).collect(from: start.map(local)).map(\.checkoutPath)
    }

    @Test("a local package reached through another local package is collected")
    func nestedLocalPackage() throws {
        for path in ["/proj/App", "/proj/Shared", "/proj/Core"] {
            try files.addDirectory(at: path)
        }
        let found = try collect(
            ["/proj/App"],
            manifests: [
                "/proj/App": manifest(["/proj/Shared"]),
                "/proj/Shared": manifest(["/proj/Core"]),
                "/proj/Core": manifest([]),
            ])
        #expect(found == ["/proj/App", "/proj/Shared", "/proj/Core"])
    }

    @Test("a cycle ends, and a package reached twice is listed once")
    func cycleAndDuplicate() throws {
        for path in ["/proj/A", "/proj/B", "/proj/C"] { try files.addDirectory(at: path) }
        let manifests = [
            "/proj/A": manifest(["/proj/B", "/proj/C"]),
            "/proj/B": manifest(["/proj/A", "/proj/C"]),
            "/proj/C": manifest(["/proj/A"]),
        ]
        #expect(
            try collect(["/proj/A", "/proj/B"], manifests: manifests)
                == ["/proj/A", "/proj/B", "/proj/C"])
    }

    @Test("a folder that a manifest names and that does not exist fails and names the folder")
    func missingPath() throws {
        try files.addDirectory(at: "/proj/A")
        #expect(throws: DomainError.fileNotFound(path: "/proj/Gone")) {
            try collect(["/proj/A"], manifests: ["/proj/A": manifest(["/proj/Gone"])])
        }
    }

    @Test("a start package whose folder is missing is kept and its manifest is not read")
    func missingStartIsKept() throws {
        #expect(try collect(["/proj/Old"], manifests: [:]) == ["/proj/Old"])
    }
}
