import DependiDomain
import DependiEntities
import Foundation

/// Reads `workspace-state.json` and `Package.resolved` through the injected file interfaces.
public struct WorkspaceStateReader: DependencySourceReading {
    static let maximumBytes = 8 * 1024 * 1024

    private let files: any FileReading
    private let directories: any DirectoryListing
    private let normalizer = PackageIdentityNormalizer()

    /// Creates a reader that uses the given file and folder interfaces.
    public init(files: any FileReading, directories: any DirectoryListing) {
        self.files = files
        self.directories = directories
    }

    /// Returns the packages of `workspace-state.json` with the folder of each checkout.
    public func resolvedPackages(sourcePackagesPath: String) throws(DomainError)
        -> [ResolvedPackage]
    {
        let base = Self.trimmingTrailingSlashes(sourcePackagesPath)
        let statePath = base + "/workspace-state.json"
        let data = try readCapped(statePath)
        let state = try WorkspaceStateDocument.decode(data, path: statePath)
        let checkoutsRoot = base + "/checkouts"
        var realCheckouts: String?
        var result: [ResolvedPackage] = []
        for dependency in state.dependencies {
            let ref = dependency.packageRef
            let fail = { (reason: String) -> DomainError in
                .fileUnreadable(
                    path: statePath,
                    reason: "version \(state.version), package \(ref.identity ?? "?"): \(reason)")
            }
            let location = ref.location ?? ""
            let identity =
                location.isEmpty
                ? PackageIdentity((ref.identity ?? "").lowercased())
                : normalizer.identity(forLocation: location)
            if identity.value.isEmpty { throw fail("no location and no identity") }
            let normalized = normalizer.normalizedLocation(of: location)
            let stateName = dependency.state?.name
            if stateName == "edited" || ref.kind == "fileSystem" || ref.kind == "localSourceControl"
            {
                let path = stateName == "edited" ? dependency.state?.path : nil
                let folder = path ?? (location.isEmpty ? dependency.state?.path : location)
                guard let folder, !folder.isEmpty else { throw fail("no folder for local package") }
                result.append(
                    ResolvedPackage(
                        identity: identity, kind: .local, normalizedLocation: normalized,
                        version: nil, revision: nil, checkoutPath: folder))
                continue
            }
            guard ref.kind == "remoteSourceControl" else {
                throw fail("unsupported package kind \(ref.kind ?? "(none)")")
            }
            guard let checkout = dependency.state?.checkoutState else {
                throw fail("no checkout state")
            }
            let subpath = dependency.subpath ?? ""
            let folder = try Self.checkedSubpath(subpath, fail: fail)
            let checkoutPath = checkoutsRoot + "/" + folder
            let rootReal: String
            if let realCheckouts {
                rootReal = realCheckouts
            } else {
                rootReal = try files.realPath(of: checkoutsRoot)
                realCheckouts = rootReal
            }
            let checkoutReal = try files.realPath(of: checkoutPath)
            let prefix = rootReal.hasSuffix("/") ? rootReal : rootReal + "/"
            guard checkoutReal.hasPrefix(prefix) else {
                throw .fileUnreadable(
                    path: checkoutPath,
                    reason: "the checkout folder is outside the checkouts folder")
            }
            result.append(
                ResolvedPackage(
                    identity: identity, kind: .remote, normalizedLocation: normalized,
                    version: checkout.version, revision: checkout.revision,
                    checkoutPath: checkoutPath))
        }
        return result
    }

    /// Returns the revision of each pin of the first `Package.resolved` file that is found.
    public func pinnedRevisions(projectDirectory: String) throws(DomainError) -> [PackageIdentity:
        String]
    {
        let base = Self.trimmingTrailingSlashes(projectDirectory)
        let names = try directories.topLevelNames(in: projectDirectory)
        let tail = "/xcshareddata/swiftpm/Package.resolved"
        var candidates: [String] = []
        for name in names where name.hasSuffix(".xcworkspace") {
            candidates.append(base + "/" + name + tail)
        }
        for name in names where name.hasSuffix(".xcodeproj") {
            candidates.append(base + "/" + name + "/project.xcworkspace" + tail)
        }
        candidates.append(base + "/Package.resolved")
        guard let path = candidates.first(where: { files.exists(at: $0) }) else { return [:] }
        let data = try readCapped(path)
        let pins = try PackageResolvedDocument.decode(data, path: path)
        var result: [PackageIdentity: String] = [:]
        for pin in pins.pins {
            let identity =
                pin.location.isEmpty
                ? PackageIdentity(pin.identity.lowercased())
                : normalizer.identity(forLocation: pin.location)
            if identity.value.isEmpty {
                throw .fileUnreadable(
                    path: path, reason: "version \(pins.version): a pin has no location")
            }
            if result[identity] != nil {
                throw .identityConflict(first: identity.value, second: pin.location)
            }
            result[identity] = pin.revision
        }
        return result
    }

    private func readCapped(_ path: String) throws(DomainError) -> Data {
        let real = try files.realPath(of: path)
        let data = try files.readRegularFile(at: real, upToBytes: Self.maximumBytes)
        if data.count > Self.maximumBytes {
            throw .fileUnreadable(path: path, reason: "the file is larger than 8 MB")
        }
        return data
    }

    private static func trimmingTrailingSlashes(_ path: String) -> String {
        var text = path
        while text.count > 1, text.hasSuffix("/") { text.removeLast() }
        return text
    }

    private static func checkedSubpath(
        _ subpath: String, fail: (String) -> DomainError
    ) throws(DomainError) -> String {
        if subpath.isEmpty { throw fail("the subpath is empty") }
        if subpath.hasPrefix("/") { throw fail("the subpath \(subpath) is absolute") }
        if subpath.split(separator: "/", omittingEmptySubsequences: false).contains("..") {
            throw fail("the subpath \(subpath) goes up a folder")
        }
        return subpath
    }
}
