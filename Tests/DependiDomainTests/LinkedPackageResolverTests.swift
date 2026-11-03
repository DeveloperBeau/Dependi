import DependiDomain
import DependiEntities
import DependiTestSupport
import TestHelpers
import Testing

@Suite("Linked package resolver", .timeLimit(.minutes(1)))
struct LinkedPackageResolverTests {
    private let normalizer = PackageIdentityNormalizer()

    private func remote(_ name: String, owner: String = "org") -> ResolvedPackage {
        ResolvedPackage(
            identity: PackageIdentity(name), kind: .remote, normalizedLocation: "\(owner)/\(name)",
            version: "1.0.0", revision: "abc", checkoutPath: "/checkouts/\(name)")
    }

    private func local(_ name: String) -> ResolvedPackage {
        ResolvedPackage(
            identity: PackageIdentity(name), kind: .local,
            normalizedLocation: "/proj/packages/\(name)",
            version: nil, revision: nil, checkoutPath: "/proj/Packages/\(name)")
    }

    private func dependency(
        _ kind: ManifestDependency.Kind, _ name: String, package: String? = nil,
        platforms: [String] = []
    ) -> ManifestDependency {
        ManifestDependency(kind: kind, name: name, packageName: package, platforms: platforms)
    }

    /// A package with one product and one regular target that has the given dependencies.
    private func simpleManifest(
        product: String, dependencies: [ManifestDependency] = [], declared: [String] = [],
        extraTargets: [ManifestTarget] = []
    ) -> PackageManifest {
        PackageManifest(
            products: [ManifestProduct(name: product, targetNames: [product])],
            targets: [ManifestTarget(name: product, kind: .regular, dependencies: dependencies)]
                + extraTargets,
            declaredDependencies: declared)
    }

    private func resolve(
        linked: [ProductReference], remote remotes: [ResolvedPackage],
        local locals: [ResolvedPackage] = [],
        manifests: [String: PackageManifest], excludes: Set<String> = [],
        platforms: Set<String>? = nil,
        buildTools: Bool = false
    ) throws(DomainError) -> (LinkResult, StubManifestReader) {
        let reader = StubManifestReader(manifests: manifests)
        let resolver = LinkedPackageResolver(manifests: reader, normalizer: normalizer)
        let result = try resolver.resolve(
            linked: linked, remotePackages: remotes, localPackages: locals, excludes: excludes,
            platformNames: platforms, includeBuildTools: buildTools)
        return (result, reader)
    }

    private func names(_ packages: [ResolvedPackage]) -> [String] { packages.map(\.identity.value) }

    // MARK: Transitive walk

    @Test(
        "a direct product and its transitive products are linked and an unused package is unreached"
    )
    func transitive() throws {
        let manifests = [
            "/checkouts/tca": simpleManifest(
                product: "TCA", dependencies: [dependency(.product, "Deps", package: "swift-deps")],
                declared: ["swift-deps"]),
            "/checkouts/swift-deps": simpleManifest(product: "Deps"),
            "/checkouts/unused": simpleManifest(product: "Unused"),
        ]
        let (result, _) = try resolve(
            linked: [ProductReference(productName: "TCA", packageName: "tca")],
            remote: [remote("tca"), remote("swift-deps"), remote("unused")], manifests: manifests)
        #expect(names(result.linked) == ["swift-deps", "tca"])
        #expect(names(result.unreached) == ["unused"])
    }

    @Test("a package that only a plugin target uses is not reached")
    func pluginOnlyDependency() throws {
        let plugin = ManifestTarget(
            name: "DocPlugin", kind: .plugin,
            dependencies: [dependency(.product, "Docc", package: "docc")])
        let manifest = simpleManifest(
            product: "Kit", dependencies: [dependency(.target, "DocPlugin")], declared: ["docc"],
            extraTargets: [plugin])
        let manifests = [
            "/checkouts/kit": manifest, "/checkouts/docc": simpleManifest(product: "Docc"),
        ]
        let (result, _) = try resolve(
            linked: [ProductReference(productName: "Kit", packageName: "kit")],
            remote: [remote("kit"), remote("docc")], manifests: manifests)
        #expect(names(result.linked) == ["kit"])
        #expect(names(result.unreached) == ["docc"])
    }

    @Test("a macro target's dependencies are followed only when build tools are included")
    func macroDependencies() throws {
        let macro = ManifestTarget(
            name: "KitMacros", kind: .macro,
            dependencies: [dependency(.product, "Syntax", package: "swift-syntax")])
        let manifest = simpleManifest(
            product: "Kit", dependencies: [dependency(.target, "KitMacros")],
            declared: ["swift-syntax"],
            extraTargets: [macro])
        let manifests = [
            "/checkouts/kit": manifest,
            "/checkouts/swift-syntax": simpleManifest(product: "Syntax"),
        ]
        let linked = [ProductReference(productName: "Kit", packageName: "kit")]
        let packages = [remote("kit"), remote("swift-syntax")]
        let without = try resolve(linked: linked, remote: packages, manifests: manifests).0
        #expect(names(without.linked) == ["kit"])
        #expect(names(without.unreached) == ["swift-syntax"])
        let with = try resolve(
            linked: linked, remote: packages, manifests: manifests, buildTools: true
        ).0
        #expect(names(with.linked) == ["kit", "swift-syntax"])
        #expect(with.unreached.isEmpty)
    }

    @Test("a cycle between two packages ends and links both")
    func cycle() throws {
        let manifests = [
            "/checkouts/a": simpleManifest(
                product: "A", dependencies: [dependency(.product, "B", package: "b")],
                declared: ["b"]),
            "/checkouts/b": simpleManifest(
                product: "B", dependencies: [dependency(.product, "A", package: "a")],
                declared: ["a"]),
        ]
        let (result, _) = try resolve(
            linked: [ProductReference(productName: "A", packageName: "a")],
            remote: [remote("a"), remote("b")], manifests: manifests)
        #expect(names(result.linked) == ["a", "b"])
    }

    @Test("a package with three linked products is read once")
    func manifestReadOnce() throws {
        let manifest = PackageManifest(
            products: ["One", "Two", "Three"].map { ManifestProduct(name: $0, targetNames: [$0]) },
            targets: ["One", "Two", "Three"].map {
                ManifestTarget(name: $0, kind: .regular, dependencies: [])
            },
            declaredDependencies: [])
        let (_, reader) = try resolve(
            linked: ["One", "Two", "Three"].map {
                ProductReference(productName: $0, packageName: "kit")
            },
            remote: [remote("kit")], manifests: ["/checkouts/kit": manifest])
        #expect(reader.readCounts == ["/checkouts/kit": 1])
    }

    // MARK: Platforms

    @Test("a dependency for another platform is ignored and one for this platform is followed")
    func platformConditions() throws {
        let manifest = simpleManifest(
            product: "Kit",
            dependencies: [
                dependency(.product, "Mac", package: "mac-only", platforms: ["macos"]),
                dependency(.product, "Phone", package: "phone", platforms: ["ios", "tvos"]),
                dependency(.product, "All", package: "everywhere"),
            ],
            declared: ["mac-only", "phone", "everywhere"])
        let manifests = [
            "/checkouts/kit": manifest, "/checkouts/mac-only": simpleManifest(product: "Mac"),
            "/checkouts/phone": simpleManifest(product: "Phone"),
            "/checkouts/everywhere": simpleManifest(product: "All"),
        ]
        let packages = [remote("kit"), remote("mac-only"), remote("phone"), remote("everywhere")]
        let linked = [ProductReference(productName: "Kit", packageName: "kit")]
        let phone = try resolve(
            linked: linked, remote: packages, manifests: manifests, platforms: ["ios"]
        ).0
        #expect(names(phone.linked) == ["everywhere", "kit", "phone"])
        let all = try resolve(
            linked: linked, remote: packages, manifests: manifests, platforms: nil
        ).0
        #expect(names(all.linked) == ["everywhere", "kit", "mac-only", "phone"])
    }

    // MARK: By name

    @Test("a name that is a target of the same package stays in the package")
    func byNameLocalTarget() throws {
        let manifest = PackageManifest(
            products: [ManifestProduct(name: "Kit", targetNames: ["Kit"])],
            targets: [
                ManifestTarget(
                    name: "Kit", kind: .regular, dependencies: [dependency(.byName, "Helper")]),
                ManifestTarget(name: "Helper", kind: .regular, dependencies: []),
            ],
            declaredDependencies: ["other"])
        let manifests = [
            "/checkouts/kit": manifest, "/checkouts/other": simpleManifest(product: "Helper"),
        ]
        let (result, _) = try resolve(
            linked: [ProductReference(productName: "Kit", packageName: "kit")],
            remote: [remote("kit"), remote("other")], manifests: manifests)
        #expect(names(result.linked) == ["kit"])
    }

    @Test("a name that is a product of a declared dependency follows that dependency")
    func byNameProduct() throws {
        let manifests = [
            "/checkouts/kit": simpleManifest(
                product: "Kit", dependencies: [dependency(.byName, "Helper")],
                declared: ["helper-pkg"]),
            "/checkouts/helper-pkg": simpleManifest(product: "Helper"),
        ]
        let (result, _) = try resolve(
            linked: [ProductReference(productName: "Kit", packageName: "kit")],
            remote: [remote("kit"), remote("helper-pkg")], manifests: manifests)
        #expect(names(result.linked) == ["helper-pkg", "kit"])
    }

    @Test("a name that two declared dependencies provide is ambiguous and names both")
    func byNameAmbiguous() {
        let manifests = [
            "/checkouts/kit": simpleManifest(
                product: "Kit", dependencies: [dependency(.byName, "Helper")],
                declared: ["one", "two"]),
            "/checkouts/one": simpleManifest(product: "Helper"),
            "/checkouts/two": simpleManifest(product: "Helper"),
        ]
        #expect(
            throws: DomainError.productAmbiguous(product: "Helper", candidates: ["one", "two"])
        ) {
            try resolve(
                linked: [ProductReference(productName: "Kit", packageName: "kit")],
                remote: [remote("kit"), remote("one"), remote("two")], manifests: manifests)
        }
    }

    // MARK: Joining products to packages

    @Test("a product with no package name is found in the local packages first")
    func localProductWithoutPackage() throws {
        let manifests = [
            "/proj/Packages/core": simpleManifest(
                product: "Core", dependencies: [dependency(.product, "Net", package: "net")],
                declared: ["net"]),
            "/checkouts/net": simpleManifest(product: "Net"),
        ]
        let (result, _) = try resolve(
            linked: [ProductReference(productName: "Core", packageName: nil)],
            remote: [remote("net")], local: [local("core")], manifests: manifests)
        #expect(names(result.linked) == ["core", "net"])
    }

    @Test("a product with no package name that two local packages provide is ambiguous")
    func localProductAmbiguous() {
        let manifests = [
            "/proj/Packages/one": simpleManifest(product: "Core"),
            "/proj/Packages/two": simpleManifest(product: "Core"),
        ]
        #expect(throws: DomainError.productAmbiguous(product: "Core", candidates: ["one", "two"])) {
            try resolve(
                linked: [ProductReference(productName: "Core", packageName: nil)], remote: [],
                local: [local("one"), local("two")], manifests: manifests)
        }
    }

    @Test("a product that no package provides is unmatched and named")
    func unmatchedProduct() {
        #expect(throws: DomainError.productUnmatched(product: "Ghost")) {
            try resolve(
                linked: [ProductReference(productName: "Ghost", packageName: nil)],
                remote: [remote("kit")],
                local: [], manifests: ["/checkouts/kit": simpleManifest(product: "Kit")])
        }
        #expect(throws: DomainError.productUnmatched(product: "Kit in package nowhere")) {
            try resolve(
                linked: [ProductReference(productName: "Kit", packageName: "nowhere")],
                remote: [remote("kit")],
                manifests: ["/checkouts/kit": simpleManifest(product: "Kit")])
        }
    }

    @Test("a package name in a different case still matches")
    func packageNameCase() throws {
        let (result, _) = try resolve(
            linked: [ProductReference(productName: "Kit", packageName: "Swift-Kit")],
            remote: [remote("swift-kit")],
            manifests: ["/checkouts/swift-kit": simpleManifest(product: "Kit")])
        #expect(names(result.linked) == ["swift-kit"])
    }

    @Test("two packages with one identity are refused and both locations are named")
    func duplicateIdentity() {
        #expect(throws: DomainError.identityConflict(first: "a/utils", second: "b/utils")) {
            try resolve(
                linked: [], remote: [remote("utils", owner: "a"), remote("utils", owner: "b")],
                manifests: [:])
        }
    }

    @Test("a local package with the identity of a remote package is refused")
    func localRemoteConflict() {
        #expect(
            throws: DomainError.identityConflict(first: "/proj/packages/kit", second: "org/kit")
        ) {
            try resolve(linked: [], remote: [remote("kit")], local: [local("kit")], manifests: [:])
        }
    }

    // MARK: Excludes

    @Test("an excluded package is removed from the linked and unreached lists")
    func excludeRemoves() throws {
        let manifests = [
            "/checkouts/kit": simpleManifest(
                product: "Kit", dependencies: [dependency(.product, "Own", package: "own")],
                declared: ["own"]),
            "/checkouts/own": simpleManifest(product: "Own"),
            "/checkouts/spare": simpleManifest(product: "Spare"),
        ]
        let (result, _) = try resolve(
            linked: [ProductReference(productName: "Kit", packageName: "kit")],
            remote: [remote("kit"), remote("own"), remote("spare")], manifests: manifests,
            excludes: ["own", "spare"])
        #expect(names(result.linked) == ["kit"])
        #expect(result.unreached.isEmpty)
    }

    @Test("an exclude that matches nothing fails and names the exclude")
    func excludeMatchesNothing() {
        #expect(throws: DomainError.unmatchedExclude("typo")) {
            try resolve(
                linked: [], remote: [remote("kit")],
                manifests: ["/checkouts/kit": simpleManifest(product: "Kit")],
                excludes: ["typo"])
        }
    }

    @Test("an exclude can name the package of a linked product that has no resolved package")
    func excludeUnmatchedProductPackage() throws {
        let (result, _) = try resolve(
            linked: [ProductReference(productName: "AppKit", packageName: "app-package")],
            remote: [], manifests: [:],
            excludes: ["app-package"])
        #expect(result.linked.isEmpty)
    }

    // MARK: Fuzz

    @Test("fuzz: the linked set equals the packages reachable in a random graph, cycles included")
    func fuzzReachability() throws {
        for seed in [SeededGenerator.defaultSeed, 5, 6, 77] as [UInt64] {
            var generator = SeededGenerator(seed: seed)
            for _ in 0..<40 {
                let count = Int.random(in: 1...8, using: &generator)
                let ids = (0..<count).map { "pkg\($0)" }
                var edges: [Int: [Int]] = [:]
                for index in 0..<count {
                    edges[index] = (0..<count).filter { _ in
                        Int.random(in: 0..<4, using: &generator) == 0
                    }
                }
                var manifests: [String: PackageManifest] = [:]
                for index in 0..<count {
                    let dependencies = edges[index]!.map {
                        dependency(.product, "P\($0)", package: ids[$0])
                    }
                    manifests["/checkouts/\(ids[index])"] = simpleManifest(
                        product: "P\(index)", dependencies: dependencies,
                        declared: edges[index]!.map { ids[$0] })
                }
                let start = Int.random(in: 0..<count, using: &generator)
                var reachable: Set<Int> = []
                var queue = [start]
                while let next = queue.popLast() {
                    guard reachable.insert(next).inserted else { continue }
                    queue.append(contentsOf: edges[next]!)
                }
                let (result, _) = try resolve(
                    linked: [ProductReference(productName: "P\(start)", packageName: ids[start])],
                    remote: ids.map { remote($0) }, manifests: manifests)
                #expect(
                    Set(names(result.linked)) == Set(reachable.map { ids[$0] }),
                    "seed \(seed) start \(start) edges \(edges)")
                #expect(
                    Set(names(result.unreached)) == Set(ids).subtracting(reachable.map { ids[$0] }))
            }
        }
    }
}
