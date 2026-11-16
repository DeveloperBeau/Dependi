import DependiDomain
import DependiEntities
import DependiTestSupport
import TestHelpers
import Testing

@Suite("Linked package resolver trait fuzz", .timeLimit(.minutes(1)))
struct LinkedPackageResolverTraitFuzzTests {
    private let names = ["T0", "T1", "T2", "T3", "T4"]

    private func subset(_ generator: inout SeededGenerator, chance: Int = 3) -> [String] {
        names.filter { _ in Int.random(in: 0..<chance, using: &generator) == 0 }
    }

    private func table(_ generator: inout SeededGenerator) -> [String: [String]] {
        var table: [String: [String]] = ["default": subset(&generator)]
        for name in names { table[name] = subset(&generator, chance: 4) }
        return table
    }

    /// The traits that are on, found by repeating until nothing changes.
    private func settle(_ start: [String], _ table: [String: [String]]) -> Set<String> {
        var on = Set(start)
        var changed = true
        while changed {
            changed = false
            for name in on {
                for more in table[name] ?? [] where on.insert(more).inserted { changed = true }
            }
        }
        return on
    }

    private func leaf(_ product: String) -> PackageManifest {
        PackageManifest(
            products: [ManifestProduct(name: product, targetNames: [product])],
            targets: [ManifestTarget(name: product, kind: .regular, dependencies: [])],
            declaredDependencies: [])
    }

    private func remote(_ name: String) -> ResolvedPackage {
        ResolvedPackage(
            identity: PackageIdentity(name), kind: .remote, normalizedLocation: "org/\(name)",
            version: "1.0.0", revision: "abc", checkoutPath: "/checkouts/\(name)")
    }

    @Test(
        "random trait tables follow exactly the dependencies whose trait is on, with no extra and none missing"
    )
    func followsExactlyTheEnabledDependencies() throws {
        var generator = SeededGenerator()
        print("trait fuzz seed: \(generator.seed)")
        var followedTotal = 0
        var skippedTotal = 0
        for round in 0..<300 {
            // The parent is linked. It asks the child for traits, some only when a parent trait is on.
            let parentTable = table(&generator)
            let childTable = table(&generator)
            let parentOn = settle(parentTable["default"] ?? [], parentTable)
            let asks: [ManifestTraitRequest]? =
                Int.random(in: 0..<4, using: &generator) == 0
                ? nil
                : (0..<Int.random(in: 0...3, using: &generator)).map { _ in
                    let pool = ["default"] + names
                    return ManifestTraitRequest(
                        name: pool[Int.random(in: 0..<pool.count, using: &generator)],
                        conditionTraits: subset(&generator, chance: 3))
                }
            let conditions = (0..<5).map { _ in subset(&generator) }
            let dependencies = conditions.enumerated().map { index, condition in
                ManifestDependency(
                    kind: .product, name: "P\(index)", packageName: "leaf\(index)", platforms: [],
                    traits: condition)
            }
            // The expected result is worked out here from the rules, not from the resolver.
            var requested: [String] = []
            if let asks {
                for ask in asks
                where ask.conditionTraits.isEmpty || !parentOn.isDisjoint(with: ask.conditionTraits)
                {
                    requested.append(ask.name)
                }
            } else {
                requested = ["default"]
            }
            let childOn = settle(requested, childTable)
            var expected = ["child", "parent"]
            for (index, condition) in conditions.enumerated()
            where condition.isEmpty || !childOn.isDisjoint(with: condition) {
                expected.append("leaf\(index)")
            }
            followedTotal += expected.count - 2
            skippedTotal += 5 - (expected.count - 2)

            var manifests: [String: PackageManifest] = [
                "/checkouts/parent": PackageManifest(
                    products: [ManifestProduct(name: "Parent", targetNames: ["Parent"])],
                    targets: [
                        ManifestTarget(
                            name: "Parent", kind: .regular,
                            dependencies: [
                                ManifestDependency(
                                    kind: .product, name: "Child", packageName: "child",
                                    platforms: [])
                            ])
                    ],
                    declaredDependencies: ["child"], traitDefinitions: parentTable,
                    traitRequests: asks.map { ["child": $0] } ?? [:]),
                "/checkouts/child": PackageManifest(
                    products: [ManifestProduct(name: "Child", targetNames: ["Child"])],
                    targets: [
                        ManifestTarget(name: "Child", kind: .regular, dependencies: dependencies)
                    ],
                    declaredDependencies: (0..<5).map { "leaf\($0)" },
                    traitDefinitions: childTable),
            ]
            for index in 0..<5 { manifests["/checkouts/leaf\(index)"] = leaf("P\(index)") }
            let resolver = LinkedPackageResolver(
                manifests: StubManifestReader(manifests: manifests),
                normalizer: PackageIdentityNormalizer())
            let result = try resolver.resolve(
                linked: [ProductReference(productName: "Parent", packageName: "parent")],
                otherLinked: [],
                remotePackages: (["parent", "child"] + (0..<5).map { "leaf\($0)" }).map(remote),
                localPackages: [], excludes: [], platformNames: nil, includeBuildTools: false)
            let actual = result.linked.map(\.identity.value)
            #expect(
                actual == expected.sorted(),
                "seed \(generator.seed) round \(round): followed \(actual), expected \(expected.sorted())"
            )
        }
        // Both directions were exercised, so the check can fail on a false positive and a false negative.
        #expect(followedTotal > 200, "seed \(generator.seed): too few followed dependencies")
        #expect(skippedTotal > 200, "seed \(generator.seed): too few skipped dependencies")
    }
}
