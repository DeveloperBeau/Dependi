/// The license information for one package, ready to be written.
public struct Acknowledgement: Hashable, Sendable, Codable {
    /// The name shown to the user.
    public let displayName: String
    /// The identity of the package.
    public let identity: PackageIdentity
    /// The normalized location of the package. It is the input of the output file name.
    public let normalizedLocation: String
    /// The license files of the package, in a fixed order.
    public let documents: [LicenseDocument]

    /// Creates an acknowledgement.
    public init(
        displayName: String,
        identity: PackageIdentity,
        normalizedLocation: String,
        documents: [LicenseDocument]
    ) {
        self.displayName = displayName
        self.identity = identity
        self.normalizedLocation = normalizedLocation
        self.documents = documents
    }
}
