import DependiDomain

/// An application target lister that returns a fixed result.
public struct StubApplicationTargets: ApplicationTargetListing {
    private let result: Result<[String], DomainError>

    /// Creates a stub from a fixed result.
    public init(_ result: Result<[String], DomainError>) {
        self.result = result
    }

    /// Implements `applicationTargets` for `StubApplicationTargets`.
    public func applicationTargets(projectFilePath: String) throws(DomainError) -> [String] {
        try result.get()
    }
}
