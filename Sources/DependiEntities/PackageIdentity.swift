/// The key that names a package. It is the last component of the package location, in lowercase.
public struct PackageIdentity: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    /// The identity text.
    public let value: String

    /// Creates an identity from text that is already normalized.
    public init(_ value: String) {
        self.value = value
    }

    /// Orders identities alphabetically by their text.
    public static func < (left: PackageIdentity, right: PackageIdentity) -> Bool {
        left.value < right.value
    }

    /// The identity text, so an identity prints as its name.
    public var description: String { value }
}
