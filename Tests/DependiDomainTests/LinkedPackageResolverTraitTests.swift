import DependiDomain
import DependiEntities
import DependiTestSupport
import TestHelpers
import Testing

@Suite("Linked package resolver traits", .timeLimit(.minutes(1)))
struct LinkedPackageResolverTraitTests {
    private let normalizer = PackageIdentityNormalizer()

    private func remote(_ name: String) -> ResolvedPackage {
        ResolvedPackage(
            identity: PackageIdentity(name), kind: .remote, normalizedLocation: "org/\(name)",
            version: "1.0.0", revision: "abc", checkoutPath: "/checkouts/\(name)")
    }

    private func gated(
        _ product: String, package: String, traits: [String], platforms: [String] = []
    ) -> ManifestDependency {
        ManifestDependency(
            kind: .product, name: product, packageName: package, platforms: platforms,
            traits: traits)
    }

    private func plain(_ product: String, package: String) -> ManifestDependency {
        gated(product, package: package, traits: [])
    }

    private func leaf(_ product: String) -> PackageManifest {
        PackageManifest(
            products: [ManifestProduct(name: product, targetNames: [product])],
            targets: [ManifestTarget(name: product, kind: .regular, dependencies: [])],
            declaredDependencies: [])
    }

    private func package(
        _ product: String, dependencies: [ManifestDependency], declared: [String],
        traits: [String: [String]] = [:], requests: [String: [ManifestTraitRequest]] = [:]
    ) -> PackageManifest {
        PackageManifest(
            products: [ManifestProduct(name: product, targetNames: [product])],
            targets: [ManifestTarget(name: product, kind: .regular, dependencies: dependencies)],
            declaredDependencies: declared, traitDefinitions: traits, traitRequests: requests)
    }

    /// The shape of SQLite.swift: two dependencies that each need a trait that is not a default.
    private func sqlite(defaults: [String] = ["SystemSQLite"]) -> PackageManifest {
        package(
            "SQLite",
            dependencies: [
                gated(
                    "SQLiteSwiftCSQLite", package: "CSQLite", traits: ["SQLiteSwiftCSQLite"]),
                gated(
                    "SQLCipher", package: "SQLCipher.swift", traits: ["SQLCipher"],
                    platforms: ["ios", "macos"]),
            ],
            declared: ["csqlite", "sqlcipher.swift"],
            traits: [
                "SystemSQLite": [], "SQLiteSwiftCSQLite": [], "SQLCipher": [],
                "default": defaults,
            ],
            requests: [
                "csqlite": [ManifestTraitRequest(name: "FTS5", conditionTraits: ["FTS5"])],
                "sqlcipher.swift": [ManifestTraitRequest(name: "default", conditionTraits: [])],
            ])
    }

    private func linked(
        _ product: String, _ packageName: String, remotes: [String],
        manifests: [String: PackageManifest], platforms: Set<String> = ["ios", "macos"]
    ) throws(DomainError) -> [String] {
        let resolver = LinkedPackageResolver(
            manifests: StubManifestReader(manifests: manifests), normalizer: normalizer)
        let result = try resolver.resolve(
            linked: [ProductReference(productName: product, packageName: packageName)],
            otherLinked: [], remotePackages: remotes.map(remote), localPackages: [],
            excludes: [], platformNames: platforms, includeBuildTools: false)
        return result.linked.map(\.identity.value)
    }

    private func sqliteWorld(
        defaults: [String], present: [String]
    ) throws(DomainError) -> [String] {
        var manifests = ["/checkouts/sqlite.swift": sqlite(defaults: defaults)]
        for name in present {
            manifests["/checkouts/\(name)"] = leaf(
                name == "csqlite" ? "SQLiteSwiftCSQLite" : "SQLCipher")
        }
        return try linked(
            "SQLite", "sqlite.swift", remotes: ["sqlite.swift"] + present, manifests: manifests)
    }

    // MARK: Regression

    @Test(
        "a product behind a trait that is off is not followed, so a missing package is not an error"
    )
    func offTraitDependencyIsNotFollowed() throws {
        #expect(try sqliteWorld(defaults: ["SystemSQLite"], present: []) == ["sqlite.swift"])
    }

    // MARK: Success

    @Test("a default trait that is the trait of a dependency makes the resolver follow it")
    func defaultTraitFollows() throws {
        let result = try sqliteWorld(defaults: ["SQLiteSwiftCSQLite"], present: ["csqlite"])
        #expect(result == ["csqlite", "sqlite.swift"])
    }

    @Test("a trait that another trait enables counts as on")
    func traitEnabledByTrait() throws {
        var manifest = sqlite(defaults: ["Umbrella"])
        manifest = PackageManifest(
            products: manifest.products, targets: manifest.targets,
            declaredDependencies: manifest.declaredDependencies,
            traitDefinitions: manifest.traitDefinitions.merging(["Umbrella": ["SQLCipher"]]) { $1 },
            traitRequests: manifest.traitRequests)
        let result = try linked(
            "SQLite", "sqlite.swift", remotes: ["sqlite.swift", "sqlcipher.swift"],
            manifests: [
                "/checkouts/sqlite.swift": manifest,
                "/checkouts/sqlcipher.swift": leaf("SQLCipher"),
            ])
        #expect(result == ["sqlcipher.swift", "sqlite.swift"])
    }

    @Test("a dependent that asks for a trait turns it on for its dependency")
    func dependentEnablesTrait() throws {
        let app = package(
            "App", dependencies: [plain("SQLite", package: "sqlite.swift")],
            declared: ["sqlite.swift"],
            requests: [
                "sqlite.swift": [
                    ManifestTraitRequest(name: "SQLiteSwiftCSQLite", conditionTraits: [])
                ]
            ])
        let result = try linked(
            "App", "app", remotes: ["app", "sqlite.swift", "csqlite"],
            manifests: [
                "/checkouts/app": app, "/checkouts/sqlite.swift": sqlite(),
                "/checkouts/csqlite": leaf("SQLiteSwiftCSQLite"),
            ])
        #expect(result == ["app", "csqlite", "sqlite.swift"])
    }

    @Test(
        "a request that has a condition counts only when a trait of the dependent is on",
        arguments: [(["Extra"], true), ([], false)])
    func conditionalRequest(defaults: [String], followed: Bool) throws {
        let app = package(
            "App", dependencies: [plain("SQLite", package: "sqlite.swift")],
            declared: ["sqlite.swift"], traits: ["Extra": [], "default": defaults],
            requests: [
                "sqlite.swift": [
                    ManifestTraitRequest(name: "default", conditionTraits: []),
                    ManifestTraitRequest(name: "SQLCipher", conditionTraits: ["Extra"]),
                ]
            ])
        let result = try linked(
            "App", "app", remotes: ["app", "sqlite.swift", "sqlcipher.swift"],
            manifests: [
                "/checkouts/app": app, "/checkouts/sqlite.swift": sqlite(),
                "/checkouts/sqlcipher.swift": leaf("SQLCipher"),
            ])
        #expect(result.contains("sqlcipher.swift") == followed)
    }

    @Test("a request found only on the second walk still turns the trait on")
    func requestFromAReachedDependentSettles() throws {
        let app = package(
            "App", dependencies: [plain("Mid", package: "mid")], declared: ["mid"])
        let mid = package(
            "Mid", dependencies: [plain("Lib", package: "lib")], declared: ["lib"],
            requests: ["lib": [ManifestTraitRequest(name: "Feature", conditionTraits: [])]])
        let lib = package(
            "Lib", dependencies: [gated("Extra", package: "extra", traits: ["Feature"])],
            declared: ["extra"], traits: ["Feature": [], "default": []])
        let result = try linked(
            "App", "app", remotes: ["app", "mid", "lib", "extra"],
            manifests: [
                "/checkouts/app": app, "/checkouts/mid": mid, "/checkouts/lib": lib,
                "/checkouts/extra": leaf("Extra"),
            ])
        #expect(result == ["app", "extra", "lib", "mid"])
    }

    @Test("a dependency that the dependent gives no trait list gets its default traits")
    func noTraitListMeansDefaults() throws {
        let app = package(
            "App", dependencies: [plain("SQLite", package: "sqlite.swift")],
            declared: ["sqlite.swift"])
        let result = try linked(
            "App", "app", remotes: ["app", "sqlite.swift", "sqlcipher.swift"],
            manifests: [
                "/checkouts/app": app, "/checkouts/sqlite.swift": sqlite(defaults: ["SQLCipher"]),
                "/checkouts/sqlcipher.swift": leaf("SQLCipher"),
            ])
        #expect(result == ["app", "sqlcipher.swift", "sqlite.swift"])
    }

    @Test("a dependency with no trait condition is still followed")
    func unconditionalDependencyIsFollowed() throws {
        let kit = package(
            "Kit", dependencies: [plain("Base", package: "base")], declared: ["base"])
        let result = try linked(
            "Kit", "kit", remotes: ["kit", "base"],
            manifests: ["/checkouts/kit": kit, "/checkouts/base": leaf("Base")])
        #expect(result == ["base", "kit"])
    }

    // MARK: Failure

    @Test("a product behind a trait that is on and that no package provides fails and names it")
    func missingProductStillFails() {
        #expect(
            throws: DomainError.productUnmatched(product: "SQLiteSwiftCSQLite in package CSQLite")
        ) {
            try sqliteWorld(defaults: ["SQLiteSwiftCSQLite"], present: [])
        }
    }

    @Test("a dependent that turns the default traits off leaves the gated trait off")
    func emptyRequestTurnsDefaultsOff() throws {
        let app = package(
            "App", dependencies: [plain("SQLite", package: "sqlite.swift")],
            declared: ["sqlite.swift"], requests: ["sqlite.swift": []])
        let result = try linked(
            "App", "app", remotes: ["app", "sqlite.swift"],
            manifests: [
                "/checkouts/app": app,
                "/checkouts/sqlite.swift": sqlite(defaults: ["SQLiteSwiftCSQLite"]),
            ])
        #expect(result == ["app", "sqlite.swift"])
    }

    @Test("a trait that is on does not override a platform that does not apply")
    func platformStillApplies() throws {
        let manifests = ["/checkouts/sqlite.swift": sqlite(defaults: ["SQLCipher"])]
        let result = try linked(
            "SQLite", "sqlite.swift", remotes: ["sqlite.swift"], manifests: manifests,
            platforms: ["watchos"])
        #expect(result == ["sqlite.swift"])
    }
}
