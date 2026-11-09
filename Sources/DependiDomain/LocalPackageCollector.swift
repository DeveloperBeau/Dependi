import DependiEntities

/// Finds every local package that a set of local packages reaches through `.package(path:)`.
public struct LocalPackageCollector: Sendable {
    private let manifests: any PackageManifestReading
    private let files: any FileReading
    private let normalizer: PackageIdentityNormalizer

    /// Creates a collector that reads manifests and resolves folders through the given interfaces.
    public init(
        manifests: any PackageManifestReading, files: any FileReading,
        normalizer: PackageIdentityNormalizer
    ) {
        self.manifests = manifests
        self.files = files
        self.normalizer = normalizer
    }

    /// Returns the start packages, then each local package that they reach, in the order found.
    ///
    /// Two spellings of one folder count as one package, so a cycle ends. A start package whose
    /// folder is missing is kept and not followed, as before. A folder that a manifest names and
    /// that does not exist fails with `fileNotFound` and its path.
    public func collect(from start: [ResolvedPackage]) throws(DomainError) -> [ResolvedPackage] {
        var result: [ResolvedPackage] = []
        var seen: Set<String> = []
        var queue = start.map { ($0, true) }
        var index = 0
        while index < queue.count {
            let (package, isStart) = queue[index]
            index += 1
            let real: String
            if isStart {
                real = (try? files.realPath(of: package.checkoutPath)) ?? package.checkoutPath
            } else {
                guard files.exists(at: package.checkoutPath) else {
                    throw .fileNotFound(path: package.checkoutPath)
                }
                real = try files.realPath(of: package.checkoutPath)
            }
            guard seen.insert(real).inserted else { continue }
            result.append(package)
            if isStart && !files.exists(at: package.checkoutPath) { continue }
            for path in try manifests.manifest(atPackagePath: package.checkoutPath)
                .localDependencyPaths
            {
                queue.append(
                    (
                        ResolvedPackage(
                            identity: normalizer.identity(forLocation: path), kind: .local,
                            normalizedLocation: normalizer.normalizedLocation(of: path),
                            version: nil, revision: nil, checkoutPath: path), false
                    ))
            }
        }
        return result
    }
}
