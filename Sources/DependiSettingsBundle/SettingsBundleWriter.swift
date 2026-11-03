import DependiDomain
import DependiEntities
import Foundation

/// Writes the Acknowledgements panes into a `Settings.bundle` folder.
///
/// The index pane is always owned by Dependi. The child panes are tracked in a manifest,
/// so cleanup removes only files that Dependi wrote before.
public struct SettingsBundleWriter: AcknowledgementWriting {
    private static let folderName = "Acknowledgements"
    private static let manifestName = ".dependi-manifest"
    private static let tableName = "Acknowledgements"
    private static let manifestLimit = 1_000_000

    private let files: any FileReading
    private let directories: any DirectoryListing
    private let writer: any FileWriting
    private let slugger: OutputNameSlugger

    /// Creates a writer from the file interfaces and the output name maker.
    public init(
        files: any FileReading,
        directories: any DirectoryListing,
        writer: any FileWriting,
        slugger: OutputNameSlugger
    ) {
        self.files = files
        self.directories = directories
        self.writer = writer
        self.slugger = slugger
    }

    /// Writes the index pane, one child pane for each acknowledgement and the manifest.
    public func write(_ acknowledgements: [Acknowledgement], intoBundleAt bundlePath: String)
        throws(DomainError)
    {
        let folder = Self.join(bundlePath, Self.folderName)
        let indexPath = Self.join(bundlePath, "\(Self.folderName).plist")
        let manifestPath = Self.join(folder, Self.manifestName)

        // Plan everything before the first write.
        var children: [(name: String, plist: [String: Any], data: Data)] = []
        var indexEntries: [[String: Any]] = []
        var seen: Set<String> = []
        for acknowledgement in acknowledgements {
            let slug = slugger.slug(
                identity: acknowledgement.identity,
                normalizedLocation: acknowledgement.normalizedLocation)
            guard seen.insert(slug).inserted else {
                throw .fileUnwritable(
                    path: Self.join(folder, "\(slug).plist"), reason: "two packages share this name"
                )
            }
            let plist = Self.childPane(acknowledgement)
            // Encoding fails here, before any write, for text that XML cannot hold.
            let data = try Self.encode(plist, path: Self.join(folder, "\(slug).plist"))
            children.append((name: "\(slug).plist", plist: plist, data: data))
            indexEntries.append([
                "Type": "PSChildPaneSpecifier",
                "Title": acknowledgement.displayName,
                "File": "\(Self.folderName)/\(slug)",
            ])
        }
        let newNames = Set(children.map(\.name))
        var leftovers: [String] = []
        try requirePlainFolder(folder, inBundle: bundlePath)
        let previous = try previousManifest(at: manifestPath)
        if files.exists(at: folder) {
            let present = try directories.topLevelNames(in: folder)
            for name in present
            where !Self.isTolerated(name) && !previous.contains(name) && !newNames.contains(name) {
                throw .fileUnwritable(
                    path: Self.join(folder, name),
                    reason: "a file that Dependi did not write is in the way")
            }
            leftovers = present.filter(Self.isTemporaryLeftover)
        }

        let index: [String: Any] = [
            "Title": Self.tableName, "StringsTable": Self.tableName,
            "PreferenceSpecifiers": indexEntries,
        ]

        let indexData = try Self.encode(index, path: indexPath)

        try writer.createDirectory(at: folder)
        // A crash inside an atomic write can leave a temporary file. It would ship in the bundle.
        for name in leftovers { try writer.removeItem(at: Self.join(folder, name)) }
        // The manifest lists old and new files first, so a stop in the middle loses no file.
        try writeIfDifferent(
            Data(Self.manifestText(previous.union(newNames)).utf8), to: manifestPath)
        for child in children {
            try writePlist(child.plist, encodedAs: child.data, to: Self.join(folder, child.name))
        }
        try writePlist(index, encodedAs: indexData, to: indexPath)
        for name in previous.subtracting(newNames).sorted()
        where files.exists(at: Self.join(folder, name)) {
            try writer.removeItem(at: Self.join(folder, name))
        }
        try writeIfDifferent(Data(Self.manifestText(newNames).utf8), to: manifestPath)
    }

    // MARK: Panes

    private static func childPane(_ acknowledgement: Acknowledgement) -> [String: Any] {
        let groups: [[String: Any]] = acknowledgement.documents.map {
            ["Type": "PSGroupSpecifier", "Title": $0.fileName, "FooterText": $0.text]
        }
        return [
            "Title": acknowledgement.displayName, "StringsTable": tableName,
            "PreferenceSpecifiers": groups,
        ]
    }

    private static func encode(_ plist: [String: Any], path: String) throws(DomainError) -> Data {
        do {
            let data = try PropertyListSerialization.data(
                fromPropertyList: plist, format: .xml, options: 0)
            // XML cannot hold a NUL, so the round trip must be checked here.
            let back = try PropertyListSerialization.propertyList(
                from: data, options: [], format: nil)
            guard let decoded = back as? NSDictionary, decoded.isEqual(to: plist) else {
                throw DomainError.fileUnwritable(path: path, reason: "the pane cannot be encoded")
            }
            return data
        } catch let error as DomainError {
            throw error
        } catch {
            throw .fileUnwritable(path: path, reason: "the pane cannot be encoded")
        }
    }

    /// Names that never block a run: the manifest, hidden files such as `.DS_Store`, and the
    /// temporary files of an interrupted write.
    private static func isTolerated(_ name: String) -> Bool {
        name.hasPrefix(".") || isTemporaryLeftover(name)
    }

    /// Whether the name is a temporary file that an interrupted write of a pane or of the
    /// manifest left behind.
    private static func isTemporaryLeftover(_ name: String) -> Bool {
        guard let range = name.range(of: ".tmp-", options: .backwards) else { return false }
        let base = name[..<range.lowerBound]
        guard UUID(uuidString: String(name[range.upperBound...])) != nil else { return false }
        return base.hasSuffix(".plist") && base != ".plist" || base == manifestName
    }

    private static func manifestText(_ names: Set<String>) -> String {
        names.sorted().map { $0 + "\n" }.joined()
    }

    private static func join(_ base: String, _ name: String) -> String {
        base.hasSuffix("/") ? base + name : base + "/" + name
    }

    /// Refuses a link, even a dangling one, where the Acknowledgements folder belongs.
    /// A link would send every write to a folder outside the bundle.
    private func requirePlainFolder(_ folder: String, inBundle bundlePath: String)
        throws(DomainError)
    {
        guard files.exists(at: folder) else { return }
        let refusal = DomainError.fileUnwritable(
            path: folder, reason: "it is a link, and Dependi does not write through links")
        let resolvedFolder: String
        let resolvedBundle: String
        do {
            resolvedFolder = try files.realPath(of: folder)
            resolvedBundle = try files.realPath(of: bundlePath)
        } catch {
            throw refusal
        }
        guard resolvedFolder == Self.join(resolvedBundle, Self.folderName) else { throw refusal }
    }

    // MARK: Manifest

    private func previousManifest(at path: String) throws(DomainError) -> Set<String> {
        guard files.exists(at: path) else { return [] }
        let real = try files.realPath(of: path)
        let data = try files.readRegularFile(at: real, upToBytes: Self.manifestLimit)
        guard let text = String(data: data, encoding: .utf8) else {
            throw .fileUnreadable(path: path, reason: "the manifest is not text")
        }
        var names: Set<String> = []
        for line in text.split(separator: "\n") {
            let name = String(line)
            let isPlainName =
                name.hasSuffix(".plist") && !name.contains("/") && !name.contains("\0")
                && !name.contains("\\")
            if isPlainName { names.insert(name) }
        }
        return names
    }

    // MARK: Writing

    private func writePlist(_ plist: [String: Any], encodedAs data: Data, to path: String)
        throws(DomainError)
    {
        guard try writeIfDifferent(data, to: path) else { return }
        try verify(plist, at: path)
    }

    /// Returns whether the file was written.
    @discardableResult
    private func writeIfDifferent(_ data: Data, to path: String) throws(DomainError) -> Bool {
        if let current = currentBytes(at: path), current == data { return false }
        try writer.write(data, toPath: path)
        return true
    }

    private func currentBytes(at path: String) -> Data? {
        guard files.exists(at: path) else { return nil }
        guard let real = try? files.realPath(of: path) else { return nil }
        return try? files.readRegularFile(at: real, upToBytes: Int.max - 1)
    }

    private func verify(_ expected: [String: Any], at path: String) throws(DomainError) {
        let real = try files.realPath(of: path)
        let data = try files.readRegularFile(at: real, upToBytes: Int.max - 1)
        guard
            let value = try? PropertyListSerialization.propertyList(
                from: data, options: [], format: nil),
            let decoded = value as? NSDictionary,
            decoded.isEqual(to: expected)
        else {
            throw .fileUnwritable(
                path: path, reason: "the file read back differs from what was written")
        }
    }
}
