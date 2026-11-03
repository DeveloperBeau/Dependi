import DependiDomain
import DependiEntities
import DependiGenerate
import DependiTestSupport
import Foundation
import Testing

@Suite("Generate feature")
struct GenerateFeatureTests {
    private func world(configuration: String? = "{}") throws -> GenerateWorld {
        let world = try GenerateWorld(configuration: configuration)
        try world.addRemote("kit")
        world.link("kit", package: "kit")
        return world
    }

    // MARK: Success

    @Test("an archive writes the acknowledgement of a linked package to the settings bundle")
    func archiveWrites() throws {
        let world = try world()
        let outcome = try world.run()
        #expect(outcome == .wrote(count: 1))
        let call = try #require(world.writer.calls.first)
        #expect(call.bundlePath == "/products/App.app/Settings.bundle")
        #expect(call.acknowledgements.map(\.displayName) == ["kit"])
        #expect(call.acknowledgements.first?.documents.map(\.text) == ["MIT License"])
        #expect(world.console.lines.contains("Dependi: running. archive build"))
        #expect(
            world.console.lines.contains(
                "Dependi: wrote 1 acknowledgements to /products/App.app/Settings.bundle"))
    }

    @Test("a second run gives the same acknowledgements")
    func idempotent() throws {
        let world = try world()
        _ = try world.run()
        let first = world.writer.calls
        _ = try world.run()
        #expect(world.writer.calls.map(\.acknowledgements) == first.map(\.acknowledgements))
    }

    @Test("a Mac Catalyst product writes into the resources folder")
    func catalystOutputPath() throws {
        let world = try world()
        world.environment["UNLOCALIZED_RESOURCES_FOLDER_PATH"] = "App.app/Contents/Resources"
        _ = try world.run()
        #expect(
            world.writer.calls.first?.bundlePath
                == "/products/App.app/Contents/Resources/Settings.bundle")
    }

    @Test("a configuration in the gate list runs on a build action")
    func listedConfigurationRuns() throws {
        let world = try world(configuration: #"{"gateConfigurations":["AppStore"]}"#)
        world.environment["ACTION"] = "build"
        world.environment["CONFIGURATION"] = "AppStore"
        #expect(try world.run() == .wrote(count: 1))
    }

    @Test("transitive packages and the packages of manual entries are written in sorted order")
    func transitiveAndManual() throws {
        let world = try GenerateWorld(
            configuration:
                #"{"manualEntries":[{"name":"Vendored","licensePath":"Vendor/Lib/LICENSE"}]}"#)
        try world.addRemote(
            "zeta",
            dependencies: [
                ManifestDependency(
                    kind: .product, name: "alpha", packageName: "alpha", platforms: [])
            ],
            declared: ["alpha"])
        try world.addRemote("alpha")
        try world.files.addDirectory(at: "/proj/Vendor/Lib")
        try world.files.addFile(
            at: "/proj/Vendor/Lib/LICENSE", contents: Data("Vendored text".utf8))
        world.link("zeta", package: "zeta")
        _ = try world.run()
        let names = world.writer.calls.first?.acknowledgements.map(\.displayName)
        #expect(names == ["alpha", "Vendored", "zeta"])
        #expect(
            world.writer.calls.first?.acknowledgements[1].documents.map(\.text) == ["Vendored text"]
        )
    }

    @Test("a local package from the project file is written")
    func localPackageFromProject() throws {
        let world = try GenerateWorld()
        try world.files.addDirectory(at: "/proj/Packages/Core")
        try world.files.addFile(
            at: "/proj/Packages/Core/LICENSE", contents: Data("Core license".utf8))
        world.manifests["/proj/Packages/Core"] = PackageManifest(
            products: [ManifestProduct(name: "Core", targetNames: ["Core"])],
            targets: [ManifestTarget(name: "Core", kind: .regular, dependencies: [])],
            declaredDependencies: [])
        world.linked = LinkedProductSet(
            products: [ProductReference(productName: "Core", packageName: nil)],
            localPackagePaths: ["/proj/Packages/Core"], supportedPlatforms: ["iphoneos"])
        _ = try world.run()
        #expect(world.writer.calls.first?.acknowledgements.map(\.displayName) == ["core"])
    }

    @Test("a dependency for another platform is left out")
    func platformConditionUsed() throws {
        let world = try GenerateWorld()
        let macOnly = ManifestDependency(
            kind: .product, name: "mac", packageName: "mac", platforms: ["macos"])
        try world.addRemote("kit", dependencies: [macOnly], declared: ["mac"])
        try world.addRemote("mac")
        world.link("kit", package: "kit")
        world.allowUnreached()
        _ = try world.run()
        #expect(world.writer.calls.first?.acknowledgements.map(\.displayName) == ["kit"])
    }

    // MARK: Skips

    @Test("a Debug build skips, writes nothing and reads no package")
    func debugSkips() throws {
        let world = try world()
        world.environment["ACTION"] = "build"
        world.environment["CONFIGURATION"] = "Debug"
        world.sourceFailure = .fileUnreadable(path: "/never", reason: "must not be read")
        let outcome = try world.run()
        guard case .skipped(let reason) = outcome else {
            Issue.record("expected a skip but got \(outcome)")
            return
        }
        #expect(reason == "configuration Debug is not in the gate list")
        #expect(world.writer.calls.isEmpty)
        #expect(world.manifestReader.readCounts.isEmpty)
        #expect(
            world.console.lines == ["Dependi: skipped. configuration Debug is not in the gate list"]
        )
    }

    @Test("a Debug build skips even when the sandbox is on")
    func debugSkipsBeforeTheSandboxCheck() throws {
        let world = try world()
        world.environment["ACTION"] = "build"
        world.environment["CONFIGURATION"] = "Debug"
        world.environment["ENABLE_USER_SCRIPT_SANDBOXING"] = "YES"
        guard case .skipped = try world.run() else {
            Issue.record("expected a skip")
            return
        }
    }

    @Test("a missing configuration skips a build action and fails an archive")
    func missingConfiguration() throws {
        let build = try GenerateWorld(configuration: nil)
        build.environment["ACTION"] = "build"
        guard case .skipped = try build.run() else {
            Issue.record("expected a skip")
            return
        }
        let archive = try GenerateWorld(configuration: nil)
        #expect(throws: DomainError.fileNotFound(path: "/proj/.dependi.json")) { try archive.run() }
    }

    // MARK: Failures

    @Test("the script sandbox being on fails an archive with a clear error")
    func sandboxOnFails() throws {
        let world = try world()
        world.environment["ENABLE_USER_SCRIPT_SANDBOXING"] = "YES"
        #expect(throws: DomainError.scriptSandboxEnabled) { try world.run() }
    }

    @Test("a permission error while reading packages is reported as the sandbox")
    func permissionErrorMeansSandbox() throws {
        let world = try world()
        world.sourceFailure = .fileUnreadable(path: "/work", reason: "Operation not permitted")
        #expect(throws: DomainError.scriptSandboxEnabled) { try world.run() }
        let other = try self.world()
        other.sourceFailure = .fileUnreadable(path: "/work", reason: "Input/output error")
        #expect(throws: DomainError.fileUnreadable(path: "/work", reason: "Input/output error")) {
            try other.run()
        }
    }

    @Test(
        "a missing build setting is named",
        arguments: [
            ("PROJECT_FILE_PATH", ["PROJECT_FILE_PATH"]), ("TARGET_NAME", ["TARGET_NAME"]),
        ])
    func missingSetting(name: String, missing: [String]) throws {
        let world = try world()
        world.environment[name] = nil
        #expect(throws: DomainError.buildContextIncomplete(missing: missing)) { try world.run() }
    }

    @Test("a missing project folder fails an archive and names it")
    func missingProjectDirectory() throws {
        let world = try world()
        world.environment["PROJECT_DIR"] = nil
        #expect(throws: DomainError.buildContextIncomplete(missing: ["PROJECT_DIR"])) {
            try world.run()
        }
    }

    @Test("an action missing inside Xcode fails")
    func missingAction() throws {
        let world = try world()
        world.environment["ACTION"] = nil
        #expect(throws: DomainError.buildContextIncomplete(missing: ["ACTION"])) { try world.run() }
    }

    @Test("a checkout at a different revision than the pinned one fails and names both")
    func revisionMismatch() throws {
        let world = try world()
        world.pinned[PackageIdentity("kit")] = "pinned-revision"
        #expect(
            throws: DomainError.revisionMismatch(
                package: "kit", pinned: "pinned-revision", checkedOut: "r1")
        ) {
            try world.run()
        }
    }

    @Test("a matching pinned revision and an unpinned package both pass")
    func revisionMatchPasses() throws {
        let world = try world()
        world.pinned[PackageIdentity("kit")] = "r1"
        world.pinned[PackageIdentity("other")] = "elsewhere"
        #expect(try world.run() == .wrote(count: 1))
    }

    @Test("a linked product that matches no package fails and names it")
    func unmatchedProduct() throws {
        let world = try world()
        world.link("Ghost", package: "ghost")
        #expect(throws: DomainError.productUnmatched(product: "Ghost in package ghost")) {
            try world.run()
        }
    }

    @Test("a resolved package that nothing reaches fails unless unreached packages are allowed")
    func unreachedPackages() throws {
        let world = try world()
        try world.addRemote("spare")
        #expect(throws: DomainError.packagesUnreached(["spare"])) { try world.run() }
        let allowed = try GenerateWorld(configuration: #"{"allowUnreached":true}"#)
        try allowed.addRemote("kit")
        try allowed.addRemote("spare")
        allowed.link("kit", package: "kit")
        #expect(try allowed.run() == .wrote(count: 1))
    }

    @Test("an exclude removes a package and an exclude that matches nothing fails")
    func excludes() throws {
        let world = try GenerateWorld(configuration: #"{"excludes":["spare"]}"#)
        try world.addRemote("kit")
        try world.addRemote("spare")
        world.link("kit", package: "kit")
        #expect(try world.run() == .wrote(count: 1))
        let typo = try GenerateWorld(configuration: #"{"excludes":["typo"]}"#)
        try typo.addRemote("kit")
        typo.link("kit", package: "kit")
        #expect(throws: DomainError.unmatchedExclude("typo")) { try typo.run() }
    }

    @Test(
        "a LICENSES folder gives its files, a LICENSE folder is skipped and a variant name is read")
    func licenseLayouts() throws {
        let world = try GenerateWorld()
        let reuse = try world.addRemote("reuse", license: nil)
        try world.files.addDirectory(at: reuse.checkoutPath + "/LICENSES")
        try world.files.addFile(
            at: reuse.checkoutPath + "/LICENSES/MIT.txt", contents: Data("mit text".utf8))
        try world.files.addFile(
            at: reuse.checkoutPath + "/LICENSES/Apache-2.0.txt", contents: Data("apache text".utf8))
        try world.files.addDirectory(at: reuse.checkoutPath + "/LICENSES/nested.txt")
        let odd = try world.addRemote("odd", license: nil)
        try world.files.addDirectory(at: odd.checkoutPath + "/LICENSE")
        try world.files.addFile(
            at: odd.checkoutPath + "/LICENSE.MIT", contents: Data("variant".utf8))
        world.link("reuse", package: "reuse")
        world.link("odd", package: "odd")
        _ = try world.run()
        let acknowledgements = try #require(world.writer.calls.first).acknowledgements
        #expect(acknowledgements.map(\.displayName) == ["odd", "reuse"])
        #expect(acknowledgements[0].documents.map(\.fileName) == ["LICENSE.MIT"])
        #expect(acknowledgements[0].documents.map(\.text) == ["variant"])
        #expect(acknowledgements[1].documents.map(\.fileName) == ["Apache-2.0.txt", "MIT.txt"])
        #expect(acknowledgements[1].documents.map(\.text) == ["apache text", "mit text"])
    }

    @Test("a package whose only LICENSE is a folder fails as missing a license")
    func licenseFolderOnlyIsMissing() throws {
        let world = try GenerateWorld()
        let package = try world.addRemote("kit", license: nil)
        try world.files.addDirectory(at: package.checkoutPath + "/LICENSE")
        world.link("kit", package: "kit")
        #expect(throws: DomainError.licenseMissing(package: "kit")) { try world.run() }
    }

    @Test("a package without a license file fails and names the package")
    func missingLicense() throws {
        let world = try GenerateWorld()
        try world.addRemote("kit", license: nil)
        world.link("kit", package: "kit")
        #expect(throws: DomainError.licenseMissing(package: "kit")) { try world.run() }
    }

    @Test("a manual entry outside the project, with an absolute path or with an empty path fails")
    func manualEntryRefused() throws {
        for path in ["../outside/LICENSE", "/etc/LICENSE", "", "Vendor/"] {
            let json = "{\"manualEntries\":[{\"name\":\"Lib\",\"licensePath\":\"\(path)\"}]}"
            let world = try GenerateWorld(configuration: json)
            try world.files.addDirectory(at: "/outside")
            try world.files.addFile(at: "/outside/LICENSE", contents: Data("x".utf8))
            try world.addRemote("kit")
            world.link("kit", package: "kit")
            #expect(
                throws: DomainError.manualEntryOutsideProject(name: "Lib", path: path),
                "path \(path)"
            ) {
                try world.run()
            }
        }
    }

    @Test("a failing writer is passed through")
    func writerFailure() throws {
        let world = try world()
        world.writerFailure = .fileUnwritable(
            path: "/products/App.app/Settings.bundle", reason: "read-only")
        #expect(
            throws: DomainError.fileUnwritable(
                path: "/products/App.app/Settings.bundle", reason: "read-only")
        ) { try world.run() }
    }

    // MARK: Output location

    @Test(
        "an output path that leaves the product, is absolute or is empty is refused before writing",
        arguments: [
            "../Other.bundle", "/abs/Other.bundle", "a/../../b",
        ])
    func badOutputPath(path: String) throws {
        let world = try GenerateWorld(configuration: "{\"outputPath\":\"\(path)\"}")
        try world.addRemote("kit")
        world.link("kit", package: "kit")
        #expect(
            throws: DomainError.invalidOutputLocation(
                path: path, reason: "the output path must be relative and stay in the product")
        ) {
            try world.run()
        }
        #expect(world.writer.calls.isEmpty)
    }

    @Test("a custom relative output path is used")
    func customOutputPath() throws {
        let world = try GenerateWorld(configuration: #"{"outputPath":"Resources/Settings.bundle"}"#)
        try world.addRemote("kit")
        world.link("kit", package: "kit")
        _ = try world.run()
        #expect(
            world.writer.calls.first?.bundlePath == "/products/App.app/Resources/Settings.bundle")
    }

    @Test("a relative product folder or a resources path that leaves the product is refused")
    func badProductLocation() throws {
        let relative = try world()
        relative.environment["TARGET_BUILD_DIR"] = "products"
        #expect(
            throws: DomainError.invalidOutputLocation(
                path: "products", reason: "TARGET_BUILD_DIR is not absolute")
        ) {
            try relative.run()
        }
        for resources in ["../App.app", "/App.app", "", "a/../.."] {
            let world = try self.world()
            world.environment["UNLOCALIZED_RESOURCES_FOLDER_PATH"] = resources
            #expect(throws: DomainError.self, "resources \(resources.debugDescription)") {
                try world.run()
            }
            #expect(world.writer.calls.isEmpty)
        }
    }
}

extension GenerateWorld {
    /// Allows packages that no linked product reaches.
    func allowUnreached() {
        try? files.removeItem(at: "/proj/.dependi.json")
        try? files.addFile(
            at: "/proj/.dependi.json", contents: Data(#"{"allowUnreached":true}"#.utf8))
    }
}

extension GenerateFeatureTests {
    @Test("a local package that arrives under two spellings of one path is one package")
    func localPackageWithTwoPaths() throws {
        let world = try GenerateWorld()
        try world.files.addDirectory(at: "/private/tmp/proj/Packages/Core")
        try world.files.addSymlink(at: "/tmp", pointingTo: "/private/tmp")
        try world.files.addFile(
            at: "/private/tmp/proj/Packages/Core/LICENSE", contents: Data("Core license".utf8))
        let local = ResolvedPackage(
            identity: PackageIdentity("core"), kind: .local,
            normalizedLocation: "/private/tmp/proj/packages/core",
            version: nil, revision: nil, checkoutPath: "/private/tmp/proj/Packages/Core")
        world.packages = [local]
        world.manifests["/private/tmp/proj/Packages/Core"] = PackageManifest(
            products: [ManifestProduct(name: "Core", targetNames: ["Core"])],
            targets: [ManifestTarget(name: "Core", kind: .regular, dependencies: [])],
            declaredDependencies: [])
        world.linked = LinkedProductSet(
            products: [ProductReference(productName: "Core", packageName: nil)],
            localPackagePaths: ["/tmp/proj/Packages/Core"], supportedPlatforms: ["iphoneos"])
        #expect(try world.run() == .wrote(count: 1))
        #expect(world.writer.calls.first?.acknowledgements.map(\.displayName) == ["core"])
    }
}
