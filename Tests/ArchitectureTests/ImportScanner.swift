import Foundation

/// Finds the modules that a Swift source file imports.
enum ImportScanner {
    private static let importLine = try! NSRegularExpression(
        pattern:
            #"^\s*(?:@\w+(?:\([^)]*\))?\s+)*(?:(?:public|internal|package|private|fileprivate)\s+)?import\s+(?:(?:struct|class|enum|protocol|func|var|let|typealias)\s+)?([A-Za-z_][A-Za-z0-9_]*)"#,
        options: [.anchorsMatchLines])

    /// Returns the imported module names in the order they appear. Comments and strings are ignored.
    static func importedModules(in source: String) -> [String] {
        let code = SwiftSourceLexer.codeOnly(source)
        var modules: [String] = []
        for line in code.split(separator: "\n", omittingEmptySubsequences: true) {
            let text = String(line)
            let range = NSRange(text.startIndex..., in: text)
            guard let match = importLine.firstMatch(in: text, range: range),
                let nameRange = Range(match.range(at: 1), in: text)
            else { continue }
            modules.append(String(text[nameRange]))
        }
        return modules
    }
}
