import DependiDomain
import DependiEntities
import DependiTestSupport
import Foundation
import Testing

@Suite("Generate skips packages with no license file", .timeLimit(.minutes(1)))
struct GenerateLicenseSkipTests {
    private static let bundleLine =
        "Dependi: wrote 1 acknowledgements to /products/App.app/Settings.bundle"

    @Test("a remote package with no license file is left out and named in a build warning")
    func remoteSkipped() throws {
        let world = try GenerateWorld()
        try world.addRemote("kit")
        try world.addRemote("bare", license: nil)
        world.link("kit", package: "kit")
        world.link("bare", package: "bare")
        #expect(try world.run() == .wrote(count: 1))
        #expect(world.writer.calls.first?.acknowledgements.map(\.displayName) == ["kit (1.0.0)"])
        #expect(
            world.console.errorLines == [
                "warning: Dependi: skipped bare: no license file in its checkout. "
                    + "Add a manualEntries item with its license, or set requireLicenses to fail the build."
            ])
    }

    @Test("the run summary counts the remote packages that were skipped")
    func summaryNamesSkips() throws {
        let world = try GenerateWorld()
        try world.addRemote("kit")
        try world.addRemote("bare", license: nil)
        world.link("kit", package: "kit")
        world.link("bare", package: "bare")
        _ = try world.run()
        #expect(world.console.lines.contains(Self.bundleLine + ", skipped 1 with no license file"))
        #expect(!world.console.lines.contains(Self.bundleLine))
    }

    @Test("two skipped packages give two warning lines in processing order and a count of two")
    func twoSkipsGiveTwoLines() throws {
        let world = try GenerateWorld()
        try world.addRemote("kit")
        try world.addRemote("aaa", license: nil)
        try world.addRemote("zzz", license: nil)
        world.link("kit", package: "kit")
        world.link("zzz", package: "zzz")
        world.link("aaa", package: "aaa")
        _ = try world.run()
        let lines = world.console.errorLines
        #expect(lines.count == 2)
        #expect(lines.first?.hasPrefix("warning: Dependi: skipped aaa: no license file") == true)
        #expect(lines.last?.hasPrefix("warning: Dependi: skipped zzz: no license file") == true)
        #expect(
            world.console.lines.contains(
                "Dependi: wrote 1 acknowledgements to /products/App.app/Settings.bundle, skipped 2 with no license file"
            ))
    }

    @Test("with no skipped package the summary keeps its short form and no warning is written")
    func summaryWithoutSkips() throws {
        let world = try GenerateWorld()
        try world.addRemote("kit")
        world.link("kit", package: "kit")
        _ = try world.run()
        #expect(world.console.lines.contains(Self.bundleLine))
        #expect(world.console.errorLines.isEmpty)
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
        #expect(
            written?.map(\.displayName) == [
                "four (1.0.0)", "one (1.0.0)", "three (1.0.0)", "two (1.0.0)",
            ])
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
        #expect(world.console.errorLines.isEmpty)
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
        #expect(world.console.lines.contains(Self.bundleLine))
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
            #expect(
                world.writer.calls.first?.acknowledgements.map(\.displayName) == ["kit (1.0.0)"])
            #expect(world.console.errorLines.isEmpty)
            #expect(world.console.lines.contains(Self.bundleLine))
        }
    }
}
