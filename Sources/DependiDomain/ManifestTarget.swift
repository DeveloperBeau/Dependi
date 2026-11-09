/// A target in a package manifest.
public struct ManifestTarget: Equatable, Sendable {
    /// The target name.
    public let name: String
    /// The target type.
    public let kind: TargetKind
    /// The dependencies of the target.
    public let dependencies: [ManifestDependency]

    /// Creates a manifest target.
    public init(name: String, kind: TargetKind, dependencies: [ManifestDependency]) {
        self.name = name
        self.kind = kind
        self.dependencies = dependencies
    }
}
