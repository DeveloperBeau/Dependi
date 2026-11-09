import Foundation

/// Picks the license files from the names in the top level of a package folder.
///
/// A name is a license stem, then any number of license tokens such as `-MIT`, `.MIT`, `-APACHE` or
/// `-2.0`, then an optional text extension. A folder named `LICENSES` matches too, and its files
/// are chosen with `licenseFileNames(inLicensesFolder:)`.
public struct LicenseLocator: Sendable {
    private static let pattern = try! NSRegularExpression(
        pattern:
            #"^((license|licence|copying|unlicense|notice|copyright)([-.](mit|apache|bsd|isc|zlib|gpl|lgpl|agpl|mpl|cc0|[0-9]+(\.[0-9]+)*))*(\.(txt|md|markdown|rst|rtf))?|licenses)$"#,
        options: [.caseInsensitive])
    private static let knownExtensions: Set<String> = ["txt", "md", "markdown", "rst", "rtf"]

    private static func rank(_ lowercasedName: String) -> Int {
        if lowercasedName.hasPrefix("license") || lowercasedName.hasPrefix("licence") { return 0 }
        if lowercasedName.hasPrefix("unlicense") { return 1 }
        if lowercasedName.hasPrefix("copying") { return 2 }
        if lowercasedName.hasPrefix("notice") { return 3 }
        return 4
    }

    /// Creates a locator.
    public init() {}

    /// Returns the files of a `LICENSES` folder that hold license text, sorted by name.
    ///
    /// It takes files with a text extension or none. Hidden files and other extensions are left out.
    public func licenseFileNames(inLicensesFolder names: [String]) -> [String] {
        names.filter { name in
            guard !name.hasPrefix(".") else { return false }
            guard let dot = name.lastIndex(of: "."), dot != name.startIndex else {
                return !name.contains(".")
            }
            return Self.knownExtensions.contains(name[name.index(after: dot)...].lowercased())
        }.sorted { ($0.lowercased(), $0) < ($1.lowercased(), $1) }
    }

    /// Returns the license file names in a fixed order: licenses, then notices, then copyright files. A `LICENSES` folder comes with the licenses.
    public func licenseFileNames(among names: [String]) -> [String] {
        let matches = names.filter { name in
            Self.pattern.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) != nil
        }
        return matches.sorted { left, right in
            let leftKey = (Self.rank(left.lowercased()), left.lowercased(), left)
            let rightKey = (Self.rank(right.lowercased()), right.lowercased(), right)
            return leftKey < rightKey
        }
    }
}
