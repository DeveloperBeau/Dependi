import DependiDomain

/// A manifest reader that answers by package path and counts how often each path is read.
public final class StubManifestReader: PackageManifestReading, @unchecked Sendable {
    private struct State: Sendable {
        var manifests: [String: PackageManifest]
        var reads: [String: Int] = [:]
    }

    private let state: LockedBox<State>

    /// Creates a reader from manifests keyed by package path.
    public init(manifests: [String: PackageManifest]) {
        state = LockedBox(State(manifests: manifests))
    }

    /// How many times each package path was read.
    public var readCounts: [String: Int] { state.withValue { $0.reads } }

    /// Implements `manifest` for `StubManifestReader`.
    public func manifest(atPackagePath path: String) throws(DomainError) -> PackageManifest {
        let manifest = state.withValue { state -> PackageManifest? in
            state.reads[path, default: 0] += 1
            return state.manifests[path]
        }
        guard let manifest else {
            throw .fileUnreadable(path: path, reason: "no manifest scripted")
        }
        return manifest
    }
}
