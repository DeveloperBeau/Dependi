import DependiEntities
import Foundation
import Testing

@Suite("Entity values", .timeLimit(.minutes(1)))
struct EntityValueTests {
    private func package(_ name: String, kind: PackageKind = .remote) -> ResolvedPackage {
        ResolvedPackage(
            identity: PackageIdentity(name), kind: kind,
            normalizedLocation: "example.com/org/\(name)",
            version: "1.0.0", revision: "abc", checkoutPath: "/checkouts/\(name)")
    }

    @Test("identities compare by their text and sort alphabetically")
    func identitiesSort() {
        let sorted = ["zeta", "alpha", "mid"].map(PackageIdentity.init).sorted()
        #expect(sorted.map(\.value) == ["alpha", "mid", "zeta"])
        #expect(PackageIdentity("a") == PackageIdentity("a"))
        #expect(PackageIdentity("a") != PackageIdentity("A"))
        #expect(PackageIdentity("a").description == "a")
    }

    @Test("two packages with the same identity but a different location are not equal")
    func packagesCompareEveryField() {
        let base = package("kit")
        let moved = ResolvedPackage(
            identity: base.identity, kind: .remote, normalizedLocation: "other.org/kit",
            version: base.version, revision: base.revision, checkoutPath: base.checkoutPath)
        #expect(base == package("kit"))
        #expect(base != moved)
        #expect(base != package("kit", kind: .local))
    }

    @Test("a package survives an encode and decode round trip")
    func packageRoundTrip() throws {
        let original = package("kit")
        let data = try JSONEncoder().encode(original)
        #expect(try JSONDecoder().decode(ResolvedPackage.self, from: data) == original)
    }

    @Test("a package kind uses its documented text")
    func packageKindText() throws {
        #expect(PackageKind.remote.rawValue == "remote")
        #expect(PackageKind.local.rawValue == "local")
        #expect(PackageKind(rawValue: "other") == nil)
    }

    @Test("a product reference keeps a missing package as nil")
    func productReferenceKeepsNil() {
        let local = ProductReference(productName: "Core", packageName: nil)
        let remote = ProductReference(productName: "Core", packageName: "swift-core")
        #expect(local != remote)
        #expect(local.packageName == nil)
    }

    @Test("an acknowledgement keeps its documents in the given order")
    func acknowledgementKeepsOrder() throws {
        let documents = [
            try LicenseDocument(fileName: "NOTICE", text: "n"),
            try LicenseDocument(fileName: "LICENSE", text: "l"),
        ]
        let acknowledgement = Acknowledgement(
            displayName: "Kit", identity: PackageIdentity("kit"), normalizedLocation: "x/kit",
            documents: documents)
        #expect(acknowledgement.documents.map(\.fileName) == ["NOTICE", "LICENSE"])
    }

    @Test("a build context keeps missing settings as nil and compares every field")
    func buildContextFields() {
        func context(_ configuration: String?) -> BuildContext {
            BuildContext(
                configuration: configuration, action: nil, platformName: nil, targetName: nil,
                projectFilePath: nil, projectDirectory: nil, buildDirectory: nil,
                targetBuildDirectory: nil, unlocalizedResourcesFolderPath: nil, wrapperName: nil,
                isScriptSandboxEnabled: nil)
        }
        #expect(context("Release") == context("Release"))
        #expect(context("Release") != context("Debug"))
        #expect(context(nil).configuration == nil)
        #expect(context(nil).isScriptSandboxEnabled == nil)
    }

    @Test("an entity error compares by case and payload")
    func entityErrorEquality() {
        #expect(EntityError.invalidVersion("a") == EntityError.invalidVersion("a"))
        #expect(EntityError.invalidVersion("a") != EntityError.invalidVersion("b"))
        #expect(EntityError.invalidVersion("a") != EntityError.invalidCommit("a"))
    }
}
