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
    ///
    /// An extra fragment may appear in `copyrightFile` only on a line that is exactly
    /// `Copyright <years> <fragment>`. Home directory fragments are never exempt.
    static func scan(
        root: URL,
        relativePaths: [String],
        extraFragments: [String] = [],
        copyrightFile: String? = nil
    ) throws -> [Violation] {
        var violations: [Violation] = []
        for relativePath in relativePaths {
            let url = root.appendingPathComponent(relativePath)
            guard let data = try? Data(contentsOf: url) else { continue }
            let text = String(decoding: data, as: UTF8.self)
            for fragment in homeDirectoryFragments where text.contains(fragment) {
                violations.append(Violation(relativePath: relativePath, fragment: fragment))
            }
            for fragment in extraFragments {
                var checked = text
                if relativePath == copyrightFile {
                    checked =
                        text
                        .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
                        .map { isCopyrightLine($0, holder: fragment) ? "" : $0 }
                        .joined(separator: "\n")
                }
                if checked.contains(fragment) {
                    violations.append(Violation(relativePath: relativePath, fragment: fragment))
                }
            }
        }
        return violations
    }

    /// Tells whether the line is exactly `Copyright <years> <holder>`, with years of digits and hyphens.
    static func isCopyrightLine(_ line: Substring, holder: String) -> Bool {
        let prefix = "Copyright "
        let suffix = " " + holder
        guard line.hasPrefix(prefix), line.hasSuffix(suffix) else { return false }
        let years = line.dropFirst(prefix.count).dropLast(suffix.count)
        return !years.isEmpty && years.allSatisfy { $0 == "-" || ("0"..."9").contains($0) }
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
