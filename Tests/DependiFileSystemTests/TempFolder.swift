import Foundation

/// A real temporary folder. It is removed after the body runs, even if permissions were changed.
struct TempFolder {
    /// The path as built from the temporary directory. It may pass through a link.
    let root: String
    /// The same folder with every link resolved by the C library, independent of the code under test.
    let real: String

    static func run<T>(_ body: (TempFolder) throws -> T) throws -> T {
        let path = FileManager.default.temporaryDirectory.path + "/dependi-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        defer { cleanUp(path) }
        guard let resolved = realpath(path, nil) else { throw POSIXError(.EIO) }
        defer { free(resolved) }
        return try body(TempFolder(root: path, real: String(cString: resolved)))
    }

    private static func cleanUp(_ path: String) {
        if let walker = FileManager.default.enumerator(atPath: path) {
            for case let name as String in walker {
                chmod(path + "/" + name, 0o755)
            }
        }
        chmod(path, 0o755)
        try? FileManager.default.removeItem(atPath: path)
    }
}
