/// Removes comments and string contents from Swift source while keeping line numbers.
enum SwiftSourceLexer {
    /// Returns the source with comments and string contents replaced by spaces.
    static func codeOnly(_ source: String) -> String {
        let characters = Array(source)
        var output: [Character] = []
        output.reserveCapacity(characters.count)
        var index = 0

        func blank(_ character: Character) -> Character { character == "\n" ? "\n" : " " }

        while index < characters.count {
            let character = characters[index]
            let next: Character? = index + 1 < characters.count ? characters[index + 1] : nil
            if character == "/", next == "/" {
                while index < characters.count, characters[index] != "\n" {
                    output.append(" ")
                    index += 1
                }
            } else if character == "/", next == "*" {
                var depth = 0
                while index < characters.count {
                    let current = characters[index]
                    let following: Character? =
                        index + 1 < characters.count ? characters[index + 1] : nil
                    if current == "/", following == "*" {
                        depth += 1
                        output.append(contentsOf: [" ", " "])
                        index += 2
                    } else if current == "*", following == "/" {
                        depth -= 1
                        output.append(contentsOf: [" ", " "])
                        index += 2
                        if depth == 0 { break }
                    } else {
                        output.append(blank(current))
                        index += 1
                    }
                }
            } else if character == "\"" || character == "#" {
                var hashes = 0
                var cursor = index
                while cursor < characters.count, characters[cursor] == "#" {
                    hashes += 1
                    cursor += 1
                }
                guard cursor < characters.count, characters[cursor] == "\"" else {
                    output.append(character)
                    index += 1
                    continue
                }
                let isMultiline =
                    cursor + 2 < characters.count && characters[cursor + 1] == "\""
                    && characters[cursor + 2] == "\""
                let quoteLength = isMultiline ? 3 : 1
                let closing =
                    String(repeating: "\"", count: quoteLength)
                    + String(repeating: "#", count: hashes)
                for _ in 0..<(hashes + quoteLength) { output.append(" ") }
                index = cursor + quoteLength
                while index < characters.count {
                    if characters[index] == "\\", hashes == 0 {
                        output.append(" ")
                        if index + 1 < characters.count {
                            output.append(blank(characters[index + 1]))
                        }
                        index += 2
                        continue
                    }
                    if matches(closing, in: characters, at: index) {
                        for _ in 0..<closing.count { output.append(" ") }
                        index += closing.count
                        break
                    }
                    output.append(blank(characters[index]))
                    index += 1
                }
            } else {
                output.append(character)
                index += 1
            }
        }
        return String(output)
    }

    private static func matches(_ text: String, in characters: [Character], at index: Int) -> Bool {
        let wanted = Array(text)
        guard index + wanted.count <= characters.count else { return false }
        return Array(characters[index..<(index + wanted.count)]) == wanted
    }
}
