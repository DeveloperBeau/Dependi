import DependiEntities

/// Checks and orders the acknowledgements before they are written.
public struct AcknowledgementAssembler: Sendable {
    private let slugger: OutputNameSlugger

    /// Creates an assembler that uses the given slugger to detect output name collisions.
    public init(slugger: OutputNameSlugger) {
        self.slugger = slugger
    }

    /// Returns the acknowledgements sorted by name without case, then identity, then output name.
    /// It fails on a package with no license, on two packages with one identity and on one output name.
    public func assemble(_ candidates: [Acknowledgement]) throws(DomainError) -> [Acknowledgement] {
        var identities: [PackageIdentity: String] = [:]
        var slugs: [String: String] = [:]
        for candidate in candidates {
            if candidate.documents.isEmpty { throw .licenseMissing(package: candidate.displayName) }
            if let first = identities[candidate.identity] {
                throw .identityConflict(first: first, second: candidate.normalizedLocation)
            }
            identities[candidate.identity] = candidate.normalizedLocation
            let slug = slugger.slug(
                identity: candidate.identity, normalizedLocation: candidate.normalizedLocation)
            if let first = slugs[slug] {
                throw .slugCollision(first: first, second: candidate.normalizedLocation)
            }
            slugs[slug] = candidate.normalizedLocation
        }
        // Plain code point order, so the result does not depend on the locale or on Unicode collation.
        return candidates.sorted { left, right in
            let leftKeys = [left.displayName.lowercased(), left.identity.value, slug(left)]
            let rightKeys = [right.displayName.lowercased(), right.identity.value, slug(right)]
            for (leftKey, rightKey) in zip(leftKeys, rightKeys) where leftKey != rightKey {
                return Self.precedes(leftKey, rightKey)
            }
            return Self.precedes(left.displayName, right.displayName)
        }
    }

    private static func precedes(_ left: String, _ right: String) -> Bool {
        left.unicodeScalars.lazy.map(\.value).lexicographicallyPrecedes(
            right.unicodeScalars.lazy.map(\.value))
    }

    private func slug(_ item: Acknowledgement) -> String {
        slugger.slug(identity: item.identity, normalizedLocation: item.normalizedLocation)
    }
}
