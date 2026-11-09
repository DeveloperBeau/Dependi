import Foundation

/// Rules that read the text of one Swift source file.
enum SourceRules {
    private static let topLevelPublicType = try! NSRegularExpression(
        pattern:
            #"\b(?:public|open)\s+(?:(?:final|indirect|package)\s+)*(?:struct|class|enum|protocol|actor|extension)\b"#
    )
    private static let globalVariable = try! NSRegularExpression(
        pattern: #"\bvar\s+\w+[^\n;]*"#)
    private static let staticStoredVariable = try! NSRegularExpression(
        pattern: #"\bstatic\s+var\b[^\n]*"#)
    private static let unsafeIsolation = try! NSRegularExpression(
        pattern: #"\bnonisolated\s*\(\s*unsafe\s*\)"#)
    private static let publicDeclaration = try! NSRegularExpression(
        pattern:
            #"^\s*(?:@\w+(?:\([^)]*\))?\s+)*(?:public|open)\s+(?:(?:final|static|class|mutating|nonmutating|override|convenience|required|indirect)\s+)*(?:func|var|let|init|subscript|struct|class|enum|protocol|actor|typealias)\b"#
    )
    private static let errorEnum = try! NSRegularExpression(
        pattern: #"\benum\s+\w+\s*:[^{]*\bError\b"#)
    private static let untypedThrows = try! NSRegularExpression(
        pattern: #"\bthrows\b(?!\s*\()"#)
    private static let parameterListOpeners = try! NSRegularExpression(
        pattern: #"\binit\s*[?!]?\s*\(|\bstatic\s+func\s+\w+\s*(?:<[^>]*>)?\s*\("#)

    private static func count(_ expression: NSRegularExpression, in text: String) -> Int {
        expression.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
    }

    /// Returns the source with everything inside braces replaced by a bare `{}`.
    private static func topLevelText(_ source: String) -> String {
        var output = ""
        var depth = 0
        for character in SwiftSourceLexer.codeOnly(source) {
            if character == "{" {
                if depth == 0 { output += "{}" }
                depth += 1
            } else if character == "}" {
                depth = max(0, depth - 1)
            } else if depth == 0 {
                output.append(character)
            }
        }
        return output
    }

    /// Counts the public types and public extensions declared at the top level of a file.
    static func topLevelPublicTypeCount(in source: String) -> Int {
        count(topLevelPublicType, in: topLevelText(source))
    }

    /// Returns the declarations that keep state outside any object: stored static variables, unsafe isolation and global variables.
    static func hiddenGlobalState(in source: String) -> [String] {
        let code = SwiftSourceLexer.codeOnly(source)
        func isStored(_ declaration: String) -> Bool {
            let beforeBrace = declaration.prefix { $0 != "{" }
            return beforeBrace.contains("=") || !declaration.contains("{")
        }
        var found: [String] = []
        func collect(_ expression: NSRegularExpression, in text: String, stored: Bool) {
            for match in expression.matches(in: text, range: NSRange(text.startIndex..., in: text))
            {
                guard let range = Range(match.range, in: text) else { continue }
                let declaration = String(text[range])
                if !stored || isStored(declaration) {
                    found.append(declaration.trimmingCharacters(in: .whitespaces))
                }
            }
        }
        collect(staticStoredVariable, in: code, stored: true)
        collect(unsafeIsolation, in: code, stored: false)
        let global = topLevelText(source)
        for match in globalVariable.matches(
            in: global, range: NSRange(global.startIndex..., in: global))
        {
            guard let range = Range(match.range, in: global) else { continue }
            let declaration = String(global[range])
            let isComputed =
                !declaration.prefix { $0 != "{" }.contains("=") && declaration.contains("{}")
            if !isComputed { found.append(declaration.trimmingCharacters(in: .whitespaces)) }
        }
        return found
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
            let documented = previous.hasPrefix("///")
            if !documented { result.append(offset + 1) }
        }
        return result
    }

    /// Value types whose default may be built with a call, such as `Set<String>()`.
    private static let valueTypeAllowlist: Set<String> = [
        "String", "Substring", "Int", "Int32", "Int64", "UInt", "UInt8", "Double", "Float", "Bool",
        "Character", "Set", "Array", "Dictionary", "Duration", "TimeInterval", "Data",
    ]

    private static func isAllowedDefault(_ value: String) -> Bool {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return true }  // a string literal, blanked by the lexer
        if ["nil", "true", "false", "[]", "[:]"].contains(text) { return true }
        if text.first.map({ $0.isNumber || $0 == "-" }) == true, !text.contains("(") { return true }
        if text.hasPrefix("."), !text.contains("(") { return true }  // an enumeration case
        let head = text.prefix { $0.isLetter || $0.isNumber || $0 == "_" }
        return valueTypeAllowlist.contains(String(head)) && !text.hasPrefix(".")
    }

    /// Returns the parameters of initializers and static functions whose default value builds an object or is not a literal.
    static func collaboratorDefaults(in source: String) -> [String] {
        let code = SwiftSourceLexer.codeOnly(source)
        let characters = Array(code)
        var found: [String] = []
        let whole = NSRange(code.startIndex..., in: code)
        for match in parameterListOpeners.matches(in: code, range: whole) {
            guard let matchRange = Range(match.range, in: code) else { continue }
            var index = code.distance(from: code.startIndex, to: matchRange.upperBound)
            var depth = 1
            var start = index
            var parameters: [String] = []
            while index < characters.count, depth > 0 {
                let character = characters[index]
                if character == "(" || character == "[" || character == "<" || character == "{" {
                    depth += 1
                }
                if character == ")" || character == "]" || character == ">" || character == "}" {
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
                let value = String(parameter[parameter.index(after: equals)...])
                if !isAllowedDefault(value) {
                    found.append(parameter.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }
        }
        return found
    }

    /// Returns the 1-based lines of test suites that declare no `.timeLimit`. Only a suite attribute at the start of a line counts.
    static func suitesWithoutTimeLimit(in source: String) -> [Int] {
        let code = SwiftSourceLexer.codeOnly(source).components(separatedBy: "\n")
        var result: [Int] = []
        for (offset, line) in code.enumerated() where line.hasPrefix("@Suite") {
            // The attribute can wrap onto the next lines, so read up to its closing bracket.
            var attribute = line
            var cursor = offset
            while !attribute.contains("struct"), !attribute.contains("class"),
                cursor + 1 < code.count, cursor - offset < 6
            {
                cursor += 1
                attribute += " " + code[cursor]
            }
            if !attribute.contains(".timeLimit") { result.append(offset + 1) }
        }
        return result
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
