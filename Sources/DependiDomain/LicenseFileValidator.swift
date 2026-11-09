import DependiEntities
import Foundation

/// Checks a license file before its text is used. It reads through `FileReading` only.
public struct LicenseFileValidator: Sendable {
    private let files: any FileReading
    private let maximumBytes: Int

    /// Creates a validator with a size limit in bytes.
    public init(files: any FileReading, maximumBytes: Int) {
        self.files = files
        self.maximumBytes = maximumBytes
    }

    /// The size limit that production uses: 1 MB.
    public static let standardMaximumBytes = 1_048_576

    /// Reads a license file inside a package folder and returns its document.
    public func document(
        named fileName: String, inFolder folder: String, root: String, owner: String
    ) throws(DomainError) -> LicenseDocument {
        let real = try files.realPath(of: folder + "/" + fileName)
        let realRoot = try files.realPath(of: root)
        guard real == realRoot || real.hasPrefix(realRoot + "/") else {
            throw .licenseOutsideCheckout(package: owner, file: fileName)
        }
        let data = try files.readRegularFile(at: real, upToBytes: maximumBytes)
        if data.count > maximumBytes { throw .licenseTooLarge(package: owner, file: fileName) }
        let text = try decode(data, owner: owner, fileName: fileName)
        for scalar in text.unicodeScalars where scalar.value < 0x20 {
            if scalar != "\t" && scalar != "\n" && scalar != "\r" && scalar != "\u{0C}" {
                throw .licenseControlCharacter(package: owner, file: fileName)
            }
        }
        do {
            return try LicenseDocument(fileName: fileName, text: text)
        } catch {
            throw .invalidLicenseName(package: owner, file: fileName)
        }
    }

    private func decode(_ data: Data, owner: String, fileName: String) throws(DomainError) -> String
    {
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) {
            if let text = String(data: data, encoding: .utf16) { return text }
            throw .licenseEncoding(package: owner, file: fileName)
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw .licenseEncoding(package: owner, file: fileName)
        }
        return text
    }
}
