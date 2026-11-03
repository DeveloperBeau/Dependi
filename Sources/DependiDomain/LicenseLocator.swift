import Foundation

/// Picks the license files from the names in the top level of a package folder.
public struct LicenseLocator: Sendable {
    private static let pattern = try! NSRegularExpression(
        pattern:
            #"^(license|licence|copying|unlicense|notice|copyright)(-mit|-apache)?(\.(txt|md|markdown|rst))?$"#,
        options: [.caseInsensitive])

    private static func rank(_ lowercasedName: String) -> Int {
        if lowercasedName.hasPrefix("license") || lowercasedName.hasPrefix("licence") { return 0 }
        if lowercasedName.hasPrefix("unlicense") { return 1 }
        if lowercasedName.hasPrefix("copying") { return 2 }
        if lowercasedName.hasPrefix("notice") { return 3 }
        return 4
    }

    /// Creates a locator.
    public init() {}

    /// Returns the license file names in a fixed order: licenses, then notices, then copyright files.
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
