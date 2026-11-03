import DependiEntities

/// Joins linked products to packages and follows the product graph to every package that ships.
public struct LinkedPackageResolver: Sendable {
    private let manifests: any PackageManifestReading
    private let normalizer: PackageIdentityNormalizer

    /// Creates a resolver that reads manifests through the given interface.
    public init(manifests: any PackageManifestReading, normalizer: PackageIdentityNormalizer) {
        self.manifests = manifests
        self.normalizer = normalizer
    }

    private enum Work {
        case product(PackageIdentity, String)
        case target(PackageIdentity, String)
    }

    /// Resolves the packages for a set of linked products.
    ///
    /// - Parameters:
    ///   - linked: The products that the target links.
    ///   - remotePackages: The resolved remote packages.
    ///   - localPackages: The local packages, each with its folder.
    ///   - excludes: Packages to leave out, by identity or location. Case does not matter. Each must match a package or a product's package name.
    ///   - platformNames: The manifest platform names that apply, or `nil` to follow every dependency.
    ///   - includeBuildTools: Whether to follow the dependencies of macro and plugin targets.
    public func resolve(
        linked: [ProductReference],
        remotePackages: [ResolvedPackage],
        localPackages: [ResolvedPackage],
        excludes rawExcludes: Set<String>,
        platformNames: Set<String>?,
        includeBuildTools: Bool
    ) throws(DomainError) -> LinkResult {
        let excludes = Set(rawExcludes.map { normalizer.identity(forLocation: $0).value })
        var packages: [PackageIdentity: ResolvedPackage] = [:]
        for package in localPackages + remotePackages {
            if let existing = packages[package.identity] {
                throw .identityConflict(
                    first: existing.normalizedLocation, second: package.normalizedLocation)
            }
            packages[package.identity] = package
        }
        try checkExcludes(rawExcludes, packages: packages, linked: linked)
        var cache: [PackageIdentity: PackageManifest] = [:]

        func manifest(_ identity: PackageIdentity) throws(DomainError) -> PackageManifest {
            if let cached = cache[identity] { return cached }
            guard let package = packages[identity] else {
                throw .productUnmatched(product: "package \(identity.value)")
            }
            let read = try manifests.manifest(atPackagePath: package.checkoutPath)
            cache[identity] = read
            return read
        }

        func owner(
            ofProduct name: String, packageName: String?, among declared: [String]
        ) throws(DomainError) -> PackageIdentity {
            // A package name that is not an identity, such as a manifest name, falls back to a search by product name.
            if let packageName {
                let wanted = normalizer.identity(forLocation: packageName)
                if packages[wanted] != nil { return wanted }
            }
            var found: [PackageIdentity] = []
            for identityText in declared {
                let identity = PackageIdentity(identityText)
                guard packages[identity] != nil else { continue }
                if try manifest(identity).products.contains(where: { $0.name == name }) {
                    found.append(identity)
                }
            }
            if found.count == 1 { return found[0] }
            if found.isEmpty {
                throw .productUnmatched(
                    product: packageName.map { "\(name) in package \($0)" } ?? name)
            }
            throw .productAmbiguous(product: name, candidates: found.map(\.value).sorted())
        }

        // Join the linked products to their packages.
        var roots: [(PackageIdentity, String)] = []
        for product in linked {
            if let name = product.packageName {
                let identity = normalizer.identity(forLocation: name)
                guard packages[identity] != nil else {
                    if excludes.contains(identity.value) { continue }
                    throw .productUnmatched(product: "\(product.productName) in package \(name)")
                }
                roots.append((identity, product.productName))
                continue
            }
            var matches: [PackageIdentity] = []
            for package in localPackages
            where try manifest(package.identity).products.contains(where: {
                $0.name == product.productName
            }) {
                matches.append(package.identity)
            }
            if matches.isEmpty {
                for package in remotePackages
                where try manifest(package.identity).products.contains(where: {
                    $0.name == product.productName
                }) {
                    matches.append(package.identity)
                }
            }
            if matches.count > 1 {
                throw .productAmbiguous(
                    product: product.productName, candidates: matches.map(\.value).sorted())
            }
            guard let match = matches.first else {
                throw .productUnmatched(product: product.productName)
            }
            roots.append((match, product.productName))
        }

        // Follow the graph.
        var reached: Set<PackageIdentity> = []
        var seen: Set<String> = []
        var stack = roots.map { Work.product($0.0, $0.1) }
        while let work = stack.popLast() {
            switch work {
            case .product(let identity, let name):
                guard seen.insert("p:\(identity.value)/\(name)").inserted else { continue }
                reached.insert(identity)
                let read = try manifest(identity)
                guard let product = read.products.first(where: { $0.name == name }) else {
                    throw .productUnmatched(product: "\(name) in package \(identity.value)")
                }
                for targetName in product.targetNames {
                    stack.append(.target(identity, targetName))
                }
            case .target(let identity, let name):
                guard seen.insert("t:\(identity.value)/\(name)").inserted else { continue }
                let read = try manifest(identity)
                guard let target = read.targets.first(where: { $0.name == name }) else {
                    throw .productUnmatched(product: "target \(name) in package \(identity.value)")
                }
                if (target.kind == .macro || target.kind == .plugin) && !includeBuildTools {
                    continue
                }
                for dependency in target.dependencies {
                    if let platformNames, !dependency.platforms.isEmpty,
                        platformNames.isDisjoint(with: dependency.platforms)
                    {
                        continue
                    }
                    switch dependency.kind {
                    case .target:
                        stack.append(.target(identity, dependency.name))
                    case .byName:
                        if read.targets.contains(where: { $0.name == dependency.name }) {
                            stack.append(.target(identity, dependency.name))
                        } else {
                            let found = try owner(
                                ofProduct: dependency.name, packageName: nil,
                                among: read.declaredDependencies)
                            stack.append(.product(found, dependency.name))
                        }
                    case .product:
                        let found = try owner(
                            ofProduct: dependency.name, packageName: dependency.packageName,
                            among: read.declaredDependencies)
                        stack.append(.product(found, dependency.name))
                    }
                }
            }
        }

        let shipped = reached.filter { !excludes.contains($0.value) }
        let linkedPackages = shipped.compactMap { packages[$0] }.sorted {
            $0.identity < $1.identity
        }
        let unreached = remotePackages.filter {
            !reached.contains($0.identity) && !excludes.contains($0.identity.value)
        }.sorted { $0.identity < $1.identity }
        return LinkResult(linked: linkedPackages, unreached: unreached)
    }

    private func checkExcludes(
        _ rawExcludes: Set<String>, packages: [PackageIdentity: ResolvedPackage],
        linked: [ProductReference]
    ) throws(DomainError) {
        let productPackages = Set(
            linked.compactMap { $0.packageName.map { normalizer.identity(forLocation: $0).value } })
        for exclude in rawExcludes.sorted() {
            let identity = normalizer.identity(forLocation: exclude)
            if packages[identity] == nil && !productPackages.contains(identity.value) {
                throw .unmatchedExclude(exclude)
            }
        }
    }
}
