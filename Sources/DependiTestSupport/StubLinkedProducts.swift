import DependiDomain

/// A linked product reader that returns a fixed result.
public struct StubLinkedProducts: LinkedProductReading {
    private let result: Result<LinkedProductSet, DomainError>

    /// Creates a stub from a fixed result.
    public init(_ result: Result<LinkedProductSet, DomainError>) {
        self.result = result
    }

    /// Implements `linkedProducts` for `StubLinkedProducts`.
    public func linkedProducts(projectFilePath: String, targetName: String) throws(DomainError)
        -> LinkedProductSet
    {
        try result.get()
    }
}
