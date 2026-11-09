import DependiDomain
import DependiEntities
import DependiTestSupport
import Foundation
import Testing

/// A project that references one local package, which reaches more local packages by path.
@Suite("Generate with nested local packages", .timeLimit(.minutes(1)))
struct GenerateNestedLocalTests {
    /// App references Packages/App. It names ../Shared, which names Core and the remote packages.
    private func world(configuration: String = "{}", linking product: String = "Shared")
        throws -> GenerateWorld
    {
        let world = try GenerateWorld(configuration: configuration)
        try world.addRemote("kit")
        try world.addRemote("spare")
        func local(
            _ name: String, paths: [String], dependencies: [ManifestDependency], declared: [String]
        ) throws {
            let path = "/proj/Packages/\(name)"
            try world.files.addDirectory(at: path)
            world.manifests[path] = PackageManifest(
                products: [ManifestProduct(name: name, targetNames: [name])],
                targets: [ManifestTarget(name: name, kind: .regular, dependencies: dependencies)],
                declaredDependencies: declared, localDependencyPaths: paths)
        }
        func productDependency(_ name: String) -> ManifestDependency {
            ManifestDependency(kind: .product, name: name, packageName: name, platforms: [])
        }
        try local(
            "App", paths: ["/proj/Packages/Shared"], dependencies: [productDependency("shared")],
            declared: ["shared"])
        try local(
            "Shared", paths: ["/proj/Packages/Core", "/proj/Packages/App"],
            dependencies: [
                ManifestDependency(kind: .byName, name: "Core", packageName: nil, platforms: []),
                productDependency("kit"), productDependency("spare"),
            ],
            declared: ["core", "app", "kit", "spare"])
        try local("Core", paths: [], dependencies: [], declared: [])
        world.linked = LinkedProductSet(
            products: [ProductReference(productName: product, packageName: nil)],
            localPackagePaths: ["/proj/Packages/App"], supportedPlatforms: ["iphoneos"])
        return world
    }

    @Test("a product found only in a nested local package resolves, and its remote packages ship")
    func nestedProductResolves() throws {
        let world = try world()
        #expect(try world.run() == .wrote(count: 2))
        let names = world.writer.calls.first?.acknowledgements.map(\.displayName)
        #expect(names == ["kit", "spare"])
        #expect(world.console.errorLines.isEmpty)
    }

    @Test("a product of a local package two levels down resolves")
    func deepProductResolves() throws {
        let world = try world(linking: "Core")
        world.allowUnreached()
        #expect(try world.run() == .wrote(count: 0))
        #expect(world.console.errorLines.isEmpty)
    }

    @Test("a remote package reached only through a nested local package can be excluded")
    func nestedRemoteExcluded() throws {
        let world = try world(configuration: #"{"excludes":["spare"]}"#)
        #expect(try world.run() == .wrote(count: 1))
        #expect(world.writer.calls.first?.acknowledgements.map(\.displayName) == ["kit"])
        #expect(world.console.errorLines.isEmpty)
    }

    @Test("an exclude that matches no package still fails and names the exclude")
    func unknownExcludeFails() throws {
        let world = try world(configuration: #"{"excludes":["typo"]}"#)
        #expect(throws: DomainError.unmatchedExclude("typo")) { try world.run() }
    }

    @Test("a nested local package path that does not exist fails and names the folder")
    func missingNestedPath() throws {
        let world = try world()
        world.manifests["/proj/Packages/Core"] = PackageManifest(
            products: [ManifestProduct(name: "Core", targetNames: ["Core"])],
            targets: [ManifestTarget(name: "Core", kind: .regular, dependencies: [])],
            declaredDependencies: [], localDependencyPaths: ["/proj/Packages/Gone"])
        #expect(throws: DomainError.fileNotFound(path: "/proj/Packages/Gone")) {
            try world.run()
        }
    }
}
