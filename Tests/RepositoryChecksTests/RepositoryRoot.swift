import Foundation

/// Locates the repository root from the path of this source file.
enum RepositoryRoot {
    static var url: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
