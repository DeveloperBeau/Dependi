import DependiDomain
import DependiEntities
import DependiTestSupport
import TestHelpers
import Testing

@Suite("Linked package resolver traits that the project picks", .timeLimit(.minutes(1)))
struct LinkedPackageResolverProjectTraitTests {
    private let sqliteURL = "https://github.com/stephencelis/SQLite.swift.git"

    private func remote(_ name: String) -> ResolvedPackage {
        ResolvedPackage(
            identity: PackageIdentity(name), kind: .remote, normalizedLocation: "org/\(name)",
            version: "1.0.0", revision: "abc", checkoutPath: "/checkouts/\(name)")
    }

    private func local(_ name: String) -> ResolvedPackage {
        ResolvedPackage(
            identity: PackageIdentity(name.lowercased()), kind: .local,
            normalizedLocation: "/work/packages/\(name.lowercased())", version: nil,
            revision: nil, checkoutPath: "/work/Packages/\(name)")
    }

    private func gated(_ product: String, package: String, traits: [String])
        -> ManifestDependency
    {
        ManifestDependency(
            kind: .product, name: product, packageName: package, platforms: [], traits: traits)
    }

    private func leaf(_ product: String) -> PackageManifest {
        PackageManifest(
            products: [ManifestProduct(name: product, targetNames: [product])],
            targets: [ManifestTarget(name: product, kind: .regular, dependencies: [])],
            declaredDependencies: [])
    }

    /// The shape of SQLite.swift, with a dependency that only a default trait turns on as well.
    private func sqlite(definitions: [String: [String]] = [:]) -> PackageManifest {
        PackageManifest(
            products: [ManifestProduct(name: "SQLite", targetNames: ["SQLite"])],
            targets: [
                ManifestTarget(
                    name: "SQLite", kind: .regular,
                    dependencies: [
                        gated(
                            "SQLiteSwiftCSQLite", package: "CSQLite",
                            traits: ["SQLiteSwiftCSQLite"]),
                        gated("Logging", package: "swift-log", traits: ["SystemSQLite"]),
                    ])
            ],
            declaredDependencies: ["csqlite", "swift-log"],
            traitDefinitions: [
                "default": ["SystemSQLite"], "SystemSQLite": [], "SQLiteSwiftCSQLite": [],
            ].merging(definitions) { $1 })
    }

    /// Links SQLite from SQLite.swift with the given project selection and returns what is followed.
    private func linkSQLite(
        _ projectTraits: [String: Set<String>], manifest: PackageManifest? = nil
    ) throws(DomainError) -> [String] {
        let resolver = LinkedPackageResolver(
            manifests: StubManifestReader(manifests: [
                "/checkouts/sqlite.swift": manifest ?? sqlite(),
                "/checkouts/csqlite": leaf("SQLiteSwiftCSQLite"),
                "/checkouts/swift-log": leaf("Logging"),
            ]),
            normalizer: PackageIdentityNormalizer())
        let result = try resolver.resolve(
            linked: [ProductReference(productName: "SQLite", packageName: "sqlite.swift")],
            otherLinked: [],
            remotePackages: ["sqlite.swift", "csqlite", "swift-log"].map(remote),
            localPackages: [], excludes: [], platformNames: nil, includeBuildTools: false,
            projectTraits: projectTraits)
        return result.linked.map(\.identity.value)
    }

    // MARK: Regression

    @Test("a trait that the project picks for SQLite.swift follows the dependency behind it")
    func listedTraitFollowsGatedDependency() throws {
        let followed = try linkSQLite([sqliteURL: ["SQLiteSwiftCSQLite"]])
        #expect(followed == ["csqlite", "sqlite.swift"])
    }

    @Test(
        "an empty pick turns the default traits off, so a default only dependency is not followed"
    )
    func emptySelectionTurnsDefaultsOff() throws {
        #expect(try linkSQLite([sqliteURL: []]) == ["sqlite.swift"])
    }

    @Test("a pick that does not name the default trait leaves it off")
    func listWithoutDefaultLeavesDefaultOff() throws {
        let followed = try linkSQLite([sqliteURL: ["SQLiteSwiftCSQLite"]])
        #expect(!followed.contains("swift-log"))
    }

    // MARK: Success

    @Test("a package that the project picks nothing for keeps its default traits")
    func absentSelectionKeepsDefaults() throws {
        #expect(try linkSQLite([:]) == ["sqlite.swift", "swift-log"])
    }

    @Test("a pick for another package leaves this package on its default traits")
    func selectionForOtherPackageIsIgnored() throws {
        let followed = try linkSQLite(["https://github.com/kean/Nuke.git": []])
        #expect(followed == ["sqlite.swift", "swift-log"])
    }

    @Test("a pick that names the default trait turns it on with the other names")
    func listWithDefaultKeepsDefaults() throws {
        let followed = try linkSQLite([sqliteURL: ["default", "SQLiteSwiftCSQLite"]])
        #expect(followed == ["csqlite", "sqlite.swift", "swift-log"])
    }

    @Test("a picked trait that turns on another trait follows the dependency of that trait")
    func listedTraitExpands() throws {
        let manifest = sqlite(definitions: ["Bundled": ["SQLiteSwiftCSQLite"]])
        let followed = try linkSQLite([sqliteURL: ["Bundled"]], manifest: manifest)
        #expect(followed == ["csqlite", "sqlite.swift"])
    }

    @Test("two locations that name one package join their picks")
    func locationsOfOnePackageJoin() throws {
        let followed = try linkSQLite([
            sqliteURL: ["SQLiteSwiftCSQLite"],
            "git@github.com:stephencelis/SQLite.swift": ["SystemSQLite"],
        ])
        #expect(followed == ["csqlite", "sqlite.swift", "swift-log"])
    }

    @Test("a default pick at one location joins a listed trait at another location of the package")
    func defaultAndListedLocationsJoin() throws {
        let followed = try linkSQLite([
            "https://github.com/stephencelis/SQLite.swift": ["default"],
            sqliteURL: ["SQLiteSwiftCSQLite"],
        ])
        #expect(followed == ["csqlite", "sqlite.swift", "swift-log"])
    }

    @Test("a default pick alone behaves like no pick")
    func defaultAloneIsNoPick() throws {
        #expect(try linkSQLite([sqliteURL: ["default"]]) == ["sqlite.swift", "swift-log"])
    }

    @Test("a trait that the project picks for a local package follows the dependency behind it")
    func localPackageSelection() throws {
        let core = PackageManifest(
            products: [ManifestProduct(name: "Core", targetNames: ["Core"])],
            targets: [
                ManifestTarget(
                    name: "Core", kind: .regular,
                    dependencies: [
                        gated("Logging", package: "swift-log", traits: ["Logging"]),
                        gated("Metrics", package: "swift-metrics", traits: ["default"]),
                    ])
            ],
            declaredDependencies: ["swift-log", "swift-metrics"],
            traitDefinitions: ["default": [], "Logging": []])
        let resolver = LinkedPackageResolver(
            manifests: StubManifestReader(manifests: [
                "/work/Packages/Core": core, "/checkouts/swift-log": leaf("Logging"),
                "/checkouts/swift-metrics": leaf("Metrics"),
            ]),
            normalizer: PackageIdentityNormalizer())
        let result = try resolver.resolve(
            linked: [ProductReference(productName: "Core", packageName: nil)], otherLinked: [],
            remotePackages: ["swift-log", "swift-metrics"].map(remote),
            localPackages: [local("Core")], excludes: [], platformNames: nil,
            includeBuildTools: false, projectTraits: ["/work/Packages/Core": ["Logging"]])
        #expect(result.linked.map(\.identity.value) == ["core", "swift-log"])
        #expect(result.unreached.map(\.identity.value) == ["swift-metrics"])
    }

    @Test("a local package that the app reaches but does not link starts with the project pick")
    func unlinkedLocalPackageSelection() throws {
        // Core asks Engine for no traits, so Engine has only what the project picks.
        let core = PackageManifest(
            products: [ManifestProduct(name: "Core", targetNames: ["Core"])],
            targets: [
                ManifestTarget(
                    name: "Core", kind: .regular,
                    dependencies: [gated("Engine", package: "Engine", traits: [])])
            ],
            declaredDependencies: ["engine"], traitRequests: ["engine": []])
        let engine = PackageManifest(
            products: [ManifestProduct(name: "Engine", targetNames: ["Engine"])],
            targets: [
                ManifestTarget(
                    name: "Engine", kind: .regular,
                    dependencies: [gated("Logging", package: "swift-log", traits: ["Fast"])])
            ],
            declaredDependencies: ["swift-log"], traitDefinitions: ["default": [], "Fast": []])
        let resolver = LinkedPackageResolver(
            manifests: StubManifestReader(manifests: [
                "/work/Packages/Core": core, "/work/Packages/Engine": engine,
                "/checkouts/swift-log": leaf("Logging"),
            ]),
            normalizer: PackageIdentityNormalizer())
        let result = try resolver.resolve(
            linked: [ProductReference(productName: "Core", packageName: nil)], otherLinked: [],
            remotePackages: [remote("swift-log")],
            localPackages: [local("Core"), local("Engine")], excludes: [], platformNames: nil,
            includeBuildTools: false, projectTraits: ["/work/Packages/Engine": ["Fast"]])
        #expect(result.linked.map(\.identity.value) == ["core", "engine", "swift-log"])
    }
}
