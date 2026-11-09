import DependiDomain
import DependiEntities
import DependiProjectFile
import DependiTestSupport
import Foundation
import Testing

@Suite("Linked products from a project file", .timeLimit(.minutes(1)))
struct LinkedProductsTests {
    @Test("an app with a direct remote package product returns it with the package identity")
    func directRemoteProduct() throws {
        let set = try FixtureWorld.read("direct-remote")
        #expect(set.products == [product("Alamofire", "alamofire")])
    }

    @Test("the path of the project file itself works like the path of the project folder")
    func projectFilePathForms() throws {
        let (_, reader) = try FixtureWorld.single("direct-remote")
        let viaFile = try reader.linkedProducts(
            projectFilePath: "/work/App/App.xcodeproj/project.pbxproj", targetName: "App")
        #expect(viaFile.products == [product("Alamofire", "alamofire")])
    }

    @Test("a framework target embedded by the app contributes its own package product")
    func embeddedFrameworkIsIncluded() throws {
        let set = try FixtureWorld.read("embedded-framework")
        #expect(set.products == [product("Alamofire", "alamofire"), product("Nuke", "nuke")])
    }

    @Test("an app extension embedded by the app contributes its products")
    func appExtensionIsIncluded() throws {
        let set = try FixtureWorld.read("app-extension")
        #expect(set.products.contains(product("Sentry", "sentry-cocoa")))
    }

    @Test("a product that the app and its extension both link appears once")
    func sharedProductIsDeduplicated() throws {
        let set = try FixtureWorld.read("app-extension")
        #expect(
            set.products == [product("Alamofire", "alamofire"), product("Sentry", "sentry-cocoa")])
    }

    @Test("an embedded target is not included when the app does not embed it")
    func unembeddedFrameworkIsNotIncluded() throws {
        let set = try FixtureWorld.read("embedded-framework", target: "Kit")
        #expect(set.products == [product("Nuke", "nuke")])
    }

    @Test(
        "products of unit test and ui test targets are excluded even when the app depends on them")
    func testOnlyProductsAreExcluded() throws {
        let set = try FixtureWorld.read("test-only")
        #expect(set.products == [product("Alamofire", "alamofire")])
    }

    @Test("products of test targets are listed apart as products of other targets")
    func testTargetProductsAreOtherProducts() throws {
        let set = try FixtureWorld.read("test-only")
        #expect(set.otherProducts == [product("Nimble", "quick"), product("Quick", "quick")])
    }

    @Test("products of a sibling target are other products of the app and the reverse")
    func siblingTargetProductsAreOtherProducts() throws {
        let first = try FixtureWorld.read("second-target")
        #expect(first.otherProducts == [product("FirebaseAuth", "firebase-ios-sdk")])
        let second = try FixtureWorld.read("second-target", target: "OtherApp")
        #expect(second.otherProducts == [product("Alamofire", "alamofire")])
    }

    @Test("a product of the app is not listed as an other product")
    func appProductsAreNotOtherProducts() throws {
        let set = try FixtureWorld.read("direct-remote")
        #expect(set.otherProducts.isEmpty)
    }

    @Test("a product of a ui test target is excluded")
    func uiTestProductsAreExcludedToo() throws {
        let set = try FixtureWorld.read("test-only")
        #expect(!set.products.contains(product("Nimble", "quick")))
    }

    @Test("a local package product has no package name and the project lists its local paths")
    func localPackageProducts() throws {
        let set = try FixtureWorld.read("local-package")
        #expect(
            set.products == [
                product("Alamofire", "alamofire"), product("LocalKit", nil),
                product("OtherKit", nil),
            ])
        #expect(set.localPackagePaths == ["/work/App/Packages/Other", "/work/Packages/LocalKit"])
    }

    @Test("two products with one name from different packages are both kept")
    func sameProductNameTwoPackages() throws {
        let set = try FixtureWorld.read("same-name")
        #expect(set.products == [product("Logging", "alpha"), product("Logging", "beta")])
    }

    @Test("products of a second target in the project do not leak into the first")
    func secondTargetDoesNotLeak() throws {
        let first = try FixtureWorld.read("second-target")
        #expect(first.products == [product("Alamofire", "alamofire")])
        let second = try FixtureWorld.read("second-target", target: "OtherApp")
        #expect(second.products == [product("FirebaseAuth", "firebase-ios-sdk")])
    }

    @Test("a dependency written as a direct target link is followed")
    func directTargetDependency() throws {
        let set = try FixtureWorld.read("target-dependency")
        #expect(set.products == [product("Alamofire", "alamofire"), product("Nuke", "nuke")])
    }

    @Test("a dependency through a container proxy in the same project is followed")
    func proxyDependencyInSameProject() throws {
        let set = try FixtureWorld.read("proxy-dependency")
        #expect(set.products == [product("Alamofire", "alamofire"), product("Nuke", "nuke")])
    }

    @Test("a reachable other project adds the products of the target it names and nothing more")
    func crossProjectReachable() throws {
        let world = FixtureWorld()
        try world.place("cross-project", at: "/work/App/App.xcodeproj")
        try world.place("cross-shared", at: "/work/Shared/Shared.xcodeproj")
        let set = try ProjectFileReader(files: world.files).linkedProducts(
            projectFilePath: "/work/App/App.xcodeproj", targetName: "App")
        #expect(set.products == [product("Alamofire", "alamofire"), product("Nuke", "nuke")])
    }

    @Test("an unreachable other project is skipped without failing")
    func crossProjectUnreachable() throws {
        let set = try FixtureWorld.read("cross-project")
        #expect(set.products == [product("Alamofire", "alamofire")])
    }

    @Test("an unreadable other project is skipped without failing")
    func crossProjectCorrupt() throws {
        let world = FixtureWorld()
        try world.place("cross-project", at: "/work/App/App.xcodeproj")
        try world.files.addDirectory(at: "/work/Shared/Shared.xcodeproj")
        try world.files.addFile(
            at: "/work/Shared/Shared.xcodeproj/project.pbxproj", contents: Data("{ nope".utf8))
        let set = try ProjectFileReader(files: world.files).linkedProducts(
            projectFilePath: "/work/App/App.xcodeproj", targetName: "App")
        #expect(set.products == [product("Alamofire", "alamofire")])
    }

    @Test("a project file written by Xcode gives its local products, paths and platform")
    func realXcodeFile() throws {
        let set = try FixtureWorld.read("real-xcode", target: "Hydra")
        #expect(
            set.products == [
                product("HydraCore", nil), product("HydraModels", nil), product("HydraUI", nil),
            ])
        #expect(
            set.localPackagePaths == [
                "/work/App/Packages/HydraCore", "/work/App/Packages/HydraModels",
                "/work/App/Packages/HydraUI",
            ])
        #expect(set.supportedPlatforms == ["macosx"])
    }

    @Test("a project folder that is a link to the real folder is read")
    func linkedProjectFolder() throws {
        let (world, reader) = try FixtureWorld.single("direct-remote")
        try world.files.addSymlink(at: "/link", pointingTo: "/work/App/App.xcodeproj")
        let set = try reader.linkedProducts(projectFilePath: "/link", targetName: "App")
        #expect(set.products == [product("Alamofire", "alamofire")])
    }
}
