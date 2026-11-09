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
            // A registry package has no checkout here. A product that links one is not matched later.
            if ref.kind == "registry" { continue }
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

    /// Returns the revision of each pin of the `Package.resolved` file that belongs to the project.
    ///
    /// Workspace files win over project files, and project files win over the root file. When
    /// several workspaces have a file, the one named like an `.xcodeproj` in the folder wins.
    /// When that does not decide, every file is read and a package pinned differently in them gets
    /// no pin, so a file of another workspace never causes a false mismatch.
    public func pinnedRevisions(projectDirectory: String) throws(DomainError) -> [PackageIdentity:
        String]
    {
        let base = Self.trimmingTrailingSlashes(projectDirectory)
        let names = try directories.topLevelNames(in: projectDirectory)
        let tail = "/xcshareddata/swiftpm/Package.resolved"
        let projectNames = Set(
            names.filter { $0.hasSuffix(".xcodeproj") }.map {
                String($0.dropLast(".xcodeproj".count))
            })
        var workspaces = names.filter { $0.hasSuffix(".xcworkspace") }
            .map { (name: $0, path: base + "/" + $0 + tail) }
            .filter { files.exists(at: $0.path) }
        if workspaces.count > 1 {
            let named = workspaces.filter {
                projectNames.contains(String($0.name.dropLast(".xcworkspace".count)))
            }
            if named.count == 1 { workspaces = named }
        }
        let projects = names.filter { $0.hasSuffix(".xcodeproj") }
            .map { base + "/" + $0 + "/project.xcworkspace" + tail }
            .filter { files.exists(at: $0) }
        let root = [base + "/Package.resolved"].filter { files.exists(at: $0) }
        let tiers = [workspaces.map(\.path), projects, root]
        guard let chosen = tiers.first(where: { !$0.isEmpty }) else { return [:] }
        var seen: [PackageIdentity: Set<String>] = [:]
        for path in chosen {
            for (identity, revision) in try pinnedRevisions(inFile: path) {
                seen[identity, default: []].insert(revision)
            }
        }
        var result: [PackageIdentity: String] = [:]
        for (identity, revisions) in seen where revisions.count == 1 {
            result[identity] = revisions.first
        }
        return result
    }

    private func pinnedRevisions(inFile path: String) throws(DomainError) -> [PackageIdentity:
        String]
    {
        let data = try readCapped(path)
        let pins = try PackageResolvedDocument.decode(data, path: path)
        var result: [PackageIdentity: String] = [:]
        for pin in pins.pins {
            guard let revision = pin.revision else { continue }
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
            result[identity] = revision
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
