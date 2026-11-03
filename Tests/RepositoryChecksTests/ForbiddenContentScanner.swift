import TestHelpers
import Foundation

/// Finds text in repository files that must never be committed.
enum ForbiddenContentScanner {
    /// One forbidden string found in one file.
    struct Violation: Equatable {
        let relativePath: String
        let fragment: String
    }

    /// Fragments that name a home directory. They are built from parts so this file stays clean.
    static var homeDirectoryFragments: [String] {
        ["/Us" + "ers/", "/ho" + "me/"]
    }

    /// Returns every forbidden fragment found in the given files, relative to `root`.
    static func scan(
        root: URL,
        relativePaths: [String],
        extraFragments: [String] = []
    ) throws -> [Violation] {
        let fragments = homeDirectoryFragments + extraFragments
        var violations: [Violation] = []
        for relativePath in relativePaths {
            let url = root.appendingPathComponent(relativePath)
            guard let data = try? Data(contentsOf: url) else { continue }
            let text = String(decoding: data, as: UTF8.self)
            for fragment in fragments where text.contains(fragment) {
                violations.append(Violation(relativePath: relativePath, fragment: fragment))
            }
        }
        return violations
    }

    /// Lists every file that git tracks or would track, so ignored files are skipped.
    static func listCandidateFiles(root: URL) throws -> [String] {
        let result = try ChildProcess.run(
            ["git", "ls-files", "--cached", "--others", "--exclude-standard"],
            workingDirectory: root
        )
        return result.output.split(separator: "\n").map(String.init)
    }
}
