import DependiEntities

/// The packages that the linked products reach, and the resolved packages that nothing reached.
public struct LinkResult: Equatable, Sendable {
    /// The packages that ship in the app, sorted by identity.
    public let linked: [ResolvedPackage]
    /// The resolved remote packages that no linked product reaches, sorted by identity.
    public let unreached: [ResolvedPackage]

    /// Creates a link result.
    public init(linked: [ResolvedPackage], unreached: [ResolvedPackage]) {
        self.linked = linked
        self.unreached = unreached
    }
}
