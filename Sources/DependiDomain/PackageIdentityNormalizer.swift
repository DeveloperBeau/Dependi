import Foundation
import DependiEntities

/// Turns a repository URL or a folder path into a package identity and a normalized location.
public struct PackageIdentityNormalizer: Sendable {
    /// Creates a normalizer.
    public init() {}

    /// Returns the normalized location: lowercase, with no scheme, user, host, trailing slash or `.git`.
    public func normalizedLocation(of location: String) -> String {
        var text = location.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = text.range(of: #"^[A-Za-z][A-Za-z0-9+.\-]*://"#, options: .regularExpression)
        {
            text.removeSubrange(range)
            if let slash = text.firstIndex(of: "/") {
                text = String(text[text.index(after: slash)...])
            }
        } else if !text.hasPrefix("/"), !text.hasPrefix("."), !text.hasPrefix("~"),
            let at = text.firstIndex(of: "@"), let colon = text[at...].firstIndex(of: ":")
        {
            text = String(text[text.index(after: colon)...])
        }
        while text.hasSuffix("/") { text.removeLast() }
        if text.lowercased().hasSuffix(".git") { text.removeLast(4) }
        while text.hasSuffix("/") { text.removeLast() }
        return text.lowercased()
    }

    /// Returns the identity: the last component of the normalized location.
    public func identity(forLocation location: String) -> PackageIdentity {
        let normalized = normalizedLocation(of: location)
        let last = normalized.split(separator: "/", omittingEmptySubsequences: true).last
        let name = last.map(String.init) ?? normalized
        return PackageIdentity(name.trimmingCharacters(in: .whitespaces))
    }
}
