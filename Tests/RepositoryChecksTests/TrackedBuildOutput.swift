import Foundation
import TestHelpers

/// Finds tracked paths that sit inside a SwiftPM scratch folder.
enum TrackedBuildOutput {
    /// One tracked path that sits inside a scratch folder.
    struct Violation: Equatable {
        /// The path git tracks, relative to the repository root.
        let relativePath: String
        /// The scratch folder component that made this path a violation.
        let directoryName: String
    }

    /// Thrown when git cannot list the index.
    struct ListingFailed: Error, CustomStringConvertible {
        /// The text git wrote.
        let output: String

        var description: String { "git ls-files failed: \(output)" }
    }

    /// Scratch folders SwiftPM writes and that git must not track.
    /// `.build` is the shared scratch path.
    /// `.build-modules` is the per-target scratch path the old gate script used.
    static let directoryNames: Set<String> = [".build", ".build-modules"]

    /// Returns one violation for each path that has a scratch folder as a component.
    /// The directory name is the first such component.
    static func violations(in relativePaths: [String]) -> [Violation] {
        var found: [Violation] = []
        for relativePath in relativePaths {
            let parts = relativePath.split(separator: "/", omittingEmptySubsequences: false)
            guard let name = parts.first(where: { directoryNames.contains(String($0)) }) else {
                continue
            }
            found.append(Violation(relativePath: relativePath, directoryName: String(name)))
        }
        return found
    }

    /// Lists the paths recorded in the git index at `root`.
    /// `-z` keeps each path whole. A newline listing quotes a special name, and that quoted text hides the folder.
    static func listTrackedPaths(root: URL) throws -> [String] {
        let result = try ChildProcess.run(
            ["git", "ls-files", "-z", "--cached"],
            workingDirectory: root
        )
        guard result.status == 0 else { throw ListingFailed(output: result.output) }
        return result.output.split(separator: "\0", omittingEmptySubsequences: true).map(
            String.init)
    }
}
