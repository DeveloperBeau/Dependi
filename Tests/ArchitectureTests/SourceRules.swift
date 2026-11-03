import Foundation

/// Rules that read the text of one Swift source file.
enum SourceRules {
    private static let topLevelPublicType = try! NSRegularExpression(
        pattern:
            #"^(?:@\w+(?:\([^)]*\))?\s+)*(?:public|open)\s+(?:final\s+)?(?:struct|class|enum|protocol|actor)\s+\w+"#
    )
    private static let publicDeclaration = try! NSRegularExpression(
        pattern:
            #"^\s*(?:@\w+(?:\([^)]*\))?\s+)*(?:public|open)\s+(?:(?:final|static|class|mutating|nonmutating|override|convenience|required|indirect)\s+)*(?:func|var|let|init|subscript|struct|class|enum|protocol|actor|typealias)\b"#
    )
    private static let errorEnum = try! NSRegularExpression(
        pattern: #"\benum\s+\w+\s*:[^{]*\bError\b"#)
    private static let untypedThrows = try! NSRegularExpression(
        pattern: #"\bthrows\b(?!\s*\()"#)
    private static let initializerKeyword = try! NSRegularExpression(
        pattern: #"\binit\s*[?!]?\s*\("#)

    private static func count(_ expression: NSRegularExpression, in text: String) -> Int {
        expression.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
    }

    /// Counts the public types declared at the top level of a file.
    static func topLevelPublicTypeCount(in source: String) -> Int {
        SwiftSourceLexer.codeOnly(source).split(separator: "\n").filter { line in
            let text = String(line)
            return count(topLevelPublicType, in: text) > 0
        }.count
    }

    /// Returns the 1-based line numbers of public declarations that have no doc comment.
    static func undocumentedPublicDeclarationLines(in source: String) -> [Int] {
        let rawLines = source.components(separatedBy: "\n")
        let codeLines = SwiftSourceLexer.codeOnly(source).components(separatedBy: "\n")
        var result: [Int] = []
        for (offset, codeLine) in codeLines.enumerated()
        where count(publicDeclaration, in: codeLine) > 0 {
            var cursor = offset - 1
            while cursor >= 0 {
                let trimmed = rawLines[cursor].trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("@") { cursor -= 1 } else { break }
            }
            let previous = cursor >= 0 ? rawLines[cursor].trimmingCharacters(in: .whitespaces) : ""
            let documented = previous.hasPrefix("///") || previous.hasSuffix("*/")
            if !documented { result.append(offset + 1) }
        }
        return result
    }

    /// Returns the initializer parameters whose collaborator type has a default value.
    static func collaboratorDefaults(in source: String) -> [String] {
        let code = SwiftSourceLexer.codeOnly(source)
        let characters = Array(code)
        var found: [String] = []
        let whole = NSRange(code.startIndex..., in: code)
        for match in initializerKeyword.matches(in: code, range: whole) {
            guard let matchRange = Range(match.range, in: code) else { continue }
            var index = code.distance(from: code.startIndex, to: matchRange.upperBound)
            var depth = 1
            var start = index
            var parameters: [String] = []
            while index < characters.count, depth > 0 {
                let character = characters[index]
                if character == "(" || character == "[" || character == "<" { depth += 1 }
                if character == ")" || character == "]" || character == ">" {
                    if character == ">" && index > 0 && characters[index - 1] == "-" {
                        index += 1
                        continue
                    }
                    depth -= 1
                    if depth == 0 {
                        parameters.append(String(characters[start..<index]))
                        break
                    }
                }
                if character == "," && depth == 1 {
                    parameters.append(String(characters[start..<index]))
                    start = index + 1
                }
                index += 1
            }
            for parameter in parameters {
                guard let equals = parameter.firstIndex(of: "="),
                    let colon = parameter.firstIndex(of: ":"), colon < equals
                else { continue }
                var type = String(parameter[parameter.index(after: colon)..<equals])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                type = type.trimmingCharacters(in: CharacterSet(charactersIn: "?!"))
                let valueTypes: Set<String> = ["String", "Substring", "StaticString"]
                let isCollaborator =
                    type.hasPrefix("any ") || type.hasPrefix("some ")
                    || (!valueTypes.contains(type)
                        && (type.hasSuffix("ing") || type.hasSuffix("able")))
                if isCollaborator {
                    found.append(parameter.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }
        }
        return found
    }

    /// Counts the enumerations that conform to `Error`.
    static func errorEnumCount(in source: String) -> Int {
        count(errorEnum, in: SwiftSourceLexer.codeOnly(source))
    }

    /// Counts uses of `throws` that have no error type.
    static func untypedThrowsCount(in source: String) -> Int {
        count(untypedThrows, in: SwiftSourceLexer.codeOnly(source))
    }

    /// Fragments that must not appear in production source, built from parts.
    static var forbiddenSourceFragments: [String] {
        [
            "--disable-" + "sandbox", "\"/bin/" + "sh\"", "\"/bin/" + "bash\"", "\"/bin/" + "zsh\"",
            "\"-" + "c\"",
        ]
    }

    /// Returns the forbidden fragments found in raw source text.
    static func forbiddenFragments(in source: String) -> [String] {
        forbiddenSourceFragments.filter { source.contains($0) }
    }
}
