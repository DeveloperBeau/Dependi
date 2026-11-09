import DependiDomain
import DependiEntities
import DependiTestSupport
import Foundation
import Testing

@Suite("Generate skips packages with no license file", .timeLimit(.minutes(1)))
struct GenerateLicenseSkipTests {
    @Test("a remote package with no license file is left out and named on the error output")
    func remoteSkipped() throws {
        let world = try GenerateWorld()
        try world.addRemote("kit")
        try world.addRemote("bare", license: nil)
        world.link("kit", package: "kit")
        world.link("bare", package: "bare")
        #expect(try world.run() == .wrote(count: 1))
        #expect(world.writer.calls.first?.acknowledgements.map(\.displayName) == ["kit"])
        #expect(world.console.errorLines == ["Dependi: skipped bare: no license file"])
    }

    @Test("a package with a license under another usual name is written and not skipped")
    func otherLicenseNamesFound() throws {
        let world = try GenerateWorld()
        for (name, file) in [("one", "LICENSE.md"), ("two", "COPYING"), ("three", "licence.txt")] {
            let package = try world.addRemote(name, license: nil)
            try world.files.addFile(
                at: package.checkoutPath + "/" + file, contents: Data("\(name) text".utf8))
            world.link(name, package: name)
        }
        let nested = try world.addRemote("four", license: nil)
        try world.files.addDirectory(at: nested.checkoutPath + "/LICENSES")
        try world.files.addFile(
            at: nested.checkoutPath + "/LICENSES/MIT.txt", contents: Data("four text".utf8))
        world.link("four", package: "four")
        #expect(try world.run() == .wrote(count: 4))
        let written = world.writer.calls.first?.acknowledgements
        #expect(written?.map(\.displayName) == ["four", "one", "three", "two"])
        #expect(
            written?.map { $0.documents.map(\.fileName) }
                == [["MIT.txt"], ["LICENSE.md"], ["licence.txt"], ["COPYING"]])
        #expect(world.console.errorLines.isEmpty)
    }

    @Test("strict mode fails on a remote package with no license file and names it")
    func strictFails() throws {
        let world = try GenerateWorld(configuration: #"{"requireLicenses":true}"#)
        try world.addRemote("kit")
        try world.addRemote("bare", license: nil)
        world.link("kit", package: "kit")
        world.link("bare", package: "bare")
        #expect(throws: DomainError.licenseMissing(package: "bare")) { try world.run() }
        #expect(world.writer.calls.isEmpty)
    }

    @Test("an excluded package with no license file gives no skip line")
    func excludedGivesNoLine() throws {
        let world = try GenerateWorld(configuration: #"{"excludes":["bare"]}"#)
        try world.addRemote("kit")
        try world.addRemote("bare", license: nil)
        world.link("kit", package: "kit")
        world.link("bare", package: "bare")
        #expect(try world.run() == .wrote(count: 1))
        #expect(world.console.errorLines.isEmpty)
    }

    @Test("a local package with no license file is left out quietly, also in strict mode")
    func localSkippedQuietly() throws {
        for configuration in ["{}", #"{"requireLicenses":true}"#] {
            let world = try GenerateWorld(configuration: configuration)
            try world.addRemote("kit")
            try world.files.addDirectory(at: "/proj/Packages/Core")
            world.manifests["/proj/Packages/Core"] = PackageManifest(
                products: [ManifestProduct(name: "Core", targetNames: ["Core"])],
                targets: [
                    ManifestTarget(
                        name: "Core", kind: .regular,
                        dependencies: [
                            ManifestDependency(
                                kind: .product, name: "kit", packageName: "kit", platforms: [])
                        ])
                ],
                declaredDependencies: ["kit"])
            world.linked = LinkedProductSet(
                products: [ProductReference(productName: "Core", packageName: nil)],
                localPackagePaths: ["/proj/Packages/Core"], supportedPlatforms: ["iphoneos"])
            #expect(try world.run() == .wrote(count: 1))
            #expect(world.writer.calls.first?.acknowledgements.map(\.displayName) == ["kit"])
            #expect(world.console.errorLines.isEmpty)
        }
    }
}
