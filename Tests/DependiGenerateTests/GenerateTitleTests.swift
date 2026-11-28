import DependiDomain
import DependiEntities
import DependiTestSupport
import Foundation
import Testing

@Suite("Generate package titles", .timeLimit(.minutes(1)))
struct GenerateTitleTests {
    private func titles(_ world: GenerateWorld) throws -> [String]? {
        _ = try world.run()
        return world.writer.calls.first?.acknowledgements.map(\.displayName)
    }

    @Test("a remote package shows its manifest name and its version")
    func remoteTitleHasNameAndVersion() throws {
        let world = try GenerateWorld()
        try world.addRemote("sqlite.swift", version: "0.16.0", manifestName: "SQLite.swift")
        world.link("sqlite.swift", package: "sqlite.swift")
        #expect(try titles(world) == ["SQLite.swift (0.16.0)"])
    }

    @Test("a remote package pinned by revision shows its name with no brackets")
    func pinnedByRevision() throws {
        let world = try GenerateWorld()
        try world.addRemote("keychain-swift", version: nil, manifestName: "KeychainSwift")
        try world.addRemote("purchases", version: "", manifestName: "RevenueCat")
        world.link("keychain-swift", package: "keychain-swift")
        world.link("purchases", package: "purchases")
        #expect(try titles(world) == ["KeychainSwift", "RevenueCat"])
    }

    @Test("a remote package with no manifest name shows its identity and its version")
    func manifestNameMissing() throws {
        let world = try GenerateWorld()
        try world.addRemote("kit")
        world.link("kit", package: "kit")
        #expect(try titles(world) == ["kit (1.0.0)"])
    }

    @Test("a blank or control character manifest name falls back to the identity")
    func unusableManifestNames() throws {
        let world = try GenerateWorld()
        try world.addRemote("blank", manifestName: "   ")
        try world.addRemote("empty", manifestName: "")
        try world.addRemote("ctl", manifestName: "Bad\u{1B}[0mName")
        for name in ["blank", "empty", "ctl"] { world.link(name, package: name) }
        #expect(try titles(world) == ["blank (1.0.0)", "ctl (1.0.0)", "empty (1.0.0)"])
    }

    @Test("a local package shows its manifest name and never a version")
    func localPackage() throws {
        let world = try GenerateWorld()
        try world.files.addDirectory(at: "/proj/Packages/Core")
        try world.files.addFile(at: "/proj/Packages/Core/LICENSE", contents: Data("Core".utf8))
        world.packages = [
            ResolvedPackage(
                identity: PackageIdentity("core"), kind: .local,
                normalizedLocation: "/proj/packages/core", version: "9.9.9", revision: nil,
                checkoutPath: "/proj/Packages/Core")
        ]
        world.manifests["/proj/Packages/Core"] = PackageManifest(
            products: [ManifestProduct(name: "Core", targetNames: ["Core"])],
            targets: [ManifestTarget(name: "Core", kind: .regular, dependencies: [])],
            declaredDependencies: [], name: "CoreKit")
        world.linked = LinkedProductSet(
            products: [ProductReference(productName: "Core", packageName: nil)],
            localPackagePaths: ["/proj/Packages/Core"], supportedPlatforms: ["iphoneos"])
        #expect(try titles(world) == ["CoreKit"])
    }

    @Test("the new titles set the sort order and a second run gives the same titles")
    func titlesSortAndRepeat() throws {
        let world = try GenerateWorld()
        try world.addRemote("a-pkg", manifestName: "Zebra")
        try world.addRemote("z-pkg", manifestName: "alpha")
        try world.addRemote("m-pkg", manifestName: "Mid")
        for name in ["a-pkg", "z-pkg", "m-pkg"] { world.link(name, package: name) }
        let first = try titles(world)
        #expect(first == ["alpha (1.0.0)", "Mid (1.0.0)", "Zebra (1.0.0)"])
        let again = try world.makeFeature().run()
        #expect(again == .wrote(count: 3))
        #expect(world.writer.calls.first?.acknowledgements.map(\.displayName) == first)
    }
}
