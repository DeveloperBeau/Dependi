import CryptoKit
import DependiEntities
import Foundation

/// Makes the file name that a package's pane is written to. It is never the raw package name.
public struct OutputNameSlugger: Sendable {
    /// Creates a slugger.
    public init() {}

    /// Returns the identity reduced to `a-z`, `0-9`, `_` and `-`, then a dash and twelve hex characters
    /// of the SHA-256 hash of the normalized location.
    public func slug(identity: PackageIdentity, normalizedLocation: String) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789_-")
        var name = String(identity.value.lowercased().map { allowed.contains($0) ? $0 : "-" })
        name = name.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        if name.isEmpty { name = "package" }
        let digest = SHA256.hash(data: Data(normalizedLocation.utf8))
        let hash = digest.prefix(6).map { String(format: "%02x", $0) }.joined()
        return "\(name)-\(hash)"
    }
}
