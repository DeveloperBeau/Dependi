/// A dependency that Dependi cannot find on its own, such as vendored code.
public struct ManualEntry: Hashable, Sendable, Codable {
    /// The name shown to the user.
    public let name: String
    /// The path of the license file, relative to the project folder.
    public let licensePath: String

    /// Creates a manual entry.
    public init(name: String, licensePath: String) {
        self.name = name
        self.licensePath = licensePath
    }
}
