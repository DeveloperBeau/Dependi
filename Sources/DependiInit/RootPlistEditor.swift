import DependiDomain
import Foundation

/// Adds the Acknowledgements pane to the `Root.plist` of a settings bundle.
struct RootPlistEditor {
    /// The name of the pane that Dependi writes.
    static let paneName = "Acknowledgements"
    /// The pane name that LicensePlist wrote.
    static let oldPaneName = "com.mono0926.LicensePlist"

    enum Change: Equatable {
        case unchanged
        case added
        case rewroteOldEntry
    }

    /// Returns the new bytes and what changed. `original` is `nil` when the file does not exist.
    static func edited(_ original: Data?) throws(DomainError) -> (data: Data, change: Change) {
        let entry: [String: Any] = [
            "Type": "PSChildPaneSpecifier", "Title": paneName, "File": paneName,
        ]
        guard let original else {
            let root: [String: Any] = ["StringsTable": "Root", "PreferenceSpecifiers": [entry]]
            return (try serialize(root, format: .xml), .added)
        }
        var format = PropertyListSerialization.PropertyListFormat.xml
        let object: Any
        do {
            object = try PropertyListSerialization.propertyList(
                from: original, options: [], format: &format)
        } catch {
            throw .initRefused(reason: "Root.plist is not a property list.")
        }
        guard var root = object as? [String: Any] else {
            throw .initRefused(reason: "Root.plist does not hold a dictionary.")
        }
        var specifiers = root["PreferenceSpecifiers"] as? [[String: Any]] ?? []
        if specifiers.contains(where: { $0["File"] as? String == paneName }) {
            return (original, .unchanged)
        }
        var change = Change.added
        if let index = specifiers.firstIndex(where: { $0["File"] as? String == oldPaneName }) {
            specifiers[index]["File"] = paneName
            change = .rewroteOldEntry
        } else {
            specifiers.append(entry)
        }
        root["PreferenceSpecifiers"] = specifiers
        return (try serialize(root, format: format == .binary ? .binary : .xml), change)
    }

    private static func serialize(
        _ root: [String: Any], format: PropertyListSerialization.PropertyListFormat
    )
        throws(DomainError) -> Data
    {
        do {
            return try PropertyListSerialization.data(
                fromPropertyList: root, format: format, options: 0)
        } catch {
            throw .initRefused(reason: "Root.plist could not be written: \(error).")
        }
    }
}
