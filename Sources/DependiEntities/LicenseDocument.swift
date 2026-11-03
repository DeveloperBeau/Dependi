/// The text of one license file and the name of that file.
public struct LicenseDocument: Hashable, Sendable, Codable {
    /// The file name only. It never holds a path.
    public let fileName: String
    /// The license text.
    public let text: String

    /// Creates a license document. The file name must be a plain name with no path separator.
    public init(fileName: String, text: String) throws(EntityError) {
        let hasSeparator = fileName.contains("/") || fileName.contains("\\")
        let hasControl = fileName.unicodeScalars.contains { $0.value < 0x20 || $0.value == 0x7F }
        guard !fileName.isEmpty, fileName != ".", fileName != "..", !hasSeparator, !hasControl
        else {
            throw .invalidLicenseFileName(fileName)
        }
        self.fileName = fileName
        self.text = text
    }
}
