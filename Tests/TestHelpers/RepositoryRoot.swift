import Foundation

/// Locates the repository root from the path of this source file.
public enum RepositoryRoot {
    /// The repository root folder.
    public static var url: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
