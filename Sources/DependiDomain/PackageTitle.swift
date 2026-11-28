import DependiEntities
import Foundation

/// Builds the title of a linked package from its manifest name and its version.
public struct PackageTitle: Sendable {
    /// Creates a title builder.
    public init() {}

    /// Returns `<name> (<version>)` for a remote package with a version, and `<name>` in every other case.
    /// The name is the manifest name. The identity stands in when the manifest name is missing, empty or holds a control character.
    /// A local package never shows a version.
    public func title(
        manifestName: String?, identity: PackageIdentity, version: String?, isRemote: Bool
    ) -> String {
        let name = Self.clean(manifestName) ?? identity.value
        guard isRemote, let version = Self.clean(version) else { return name }
        return name + " (" + version + ")"
    }

    /// The text without the white space around it, or nil if it is empty or holds a control character.
    private static func clean(_ text: String?) -> String? {
        guard let text else { return nil }
        let hasControl = text.unicodeScalars.contains { $0.properties.generalCategory == .control }
        if hasControl { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }
}
