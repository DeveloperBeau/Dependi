import DependiDomain
import Foundation

extension DomainError {
    /// The error for a project file that the editor cannot change without a risk of damage.
    static func unsafeProject(path: String, why: String) -> DomainError {
        .fileUnreadable(path: path, reason: "Dependi cannot edit this project file safely: \(why)")
    }
}

/// Splits the text of a project file into spans, so that edits can use byte positions.
///
/// A comment is skipped, so a brace or a key inside a comment never counts. A quoted string is one
/// span, so a brace or a key inside a string never counts either.
struct PBXTextScanner {
    /// One `key = value;` pair of a dictionary, as indexes into `spans`.
    struct Entry {
        let key: String
        let keyIndex: Int
        let valueFirst: Int
        let valueLast: Int
    }

    let bytes: [UInt8]
    let spans: [PBXTextSpan]
    private let path: String
    private let closers: [Int: Int]
    private let objectEntries: [String: Entry]

    /// Scans the bytes. Any text that is not a well formed project file fails.
    init(bytes: [UInt8], path: String) throws(DomainError) {
        let spans = try Self.split(bytes, path: path)
        var closers: [Int: Int] = [:]
        var open: [Int] = []
        for (index, span) in spans.enumerated() where span.kind == .punctuation {
            switch bytes[span.range.lowerBound] {
            case UInt8(ascii: "{"), UInt8(ascii: "("): open.append(index)
            case UInt8(ascii: "}"), UInt8(ascii: ")"):
                guard let start = open.popLast(),
                    bytes[spans[start].range.lowerBound]
                        == Self.opener(of: bytes[span.range.lowerBound])
                else { throw .unsafeProject(path: path, why: "the brackets do not match") }
                closers[start] = index
            default: break
            }
        }
        guard open.isEmpty, spans.first.map({ bytes[$0.range.lowerBound] }) == UInt8(ascii: "{"),
            closers[0] == spans.count - 1
        else { throw .unsafeProject(path: path, why: "the file is not one dictionary") }
        let top = try Self.entries(spans: spans, closers: closers, bytes: bytes, at: 0, path: path)
        guard let objects = top.first(where: { $0.key == "objects" }),
            Self.isOpen(spans, bytes, objects.valueFirst, "{")
        else { throw .unsafeProject(path: path, why: "the objects table is missing") }
        var table: [String: Entry] = [:]
        for entry in try Self.entries(
            spans: spans, closers: closers, bytes: bytes, at: objects.valueFirst, path: path)
        {
            table[entry.key] = entry
        }
        self.bytes = bytes
        self.path = path
        self.spans = spans
        self.closers = closers
        self.objectEntries = table
    }

    private static func opener(of closer: UInt8) -> UInt8 {
        closer == UInt8(ascii: "}") ? UInt8(ascii: "{") : UInt8(ascii: "(")
    }

    private static func isOpen(
        _ spans: [PBXTextSpan], _ bytes: [UInt8], _ index: Int, _ text: Character
    )
        -> Bool
    {
        spans[index].kind == .punctuation && bytes[spans[index].range.lowerBound] == text.asciiValue
    }

    private static func isWordByte(_ byte: UInt8) -> Bool {
        switch byte {
        case UInt8(ascii: "a")...UInt8(ascii: "z"), UInt8(ascii: "A")...UInt8(ascii: "Z"),
            UInt8(ascii: "0")...UInt8(ascii: "9"), UInt8(ascii: "_"), UInt8(ascii: "$"),
            UInt8(ascii: "/"), UInt8(ascii: "."), UInt8(ascii: ":"), UInt8(ascii: "-"):
            return true
        default: return false
        }
    }

    private static func split(_ bytes: [UInt8], path: String) throws(DomainError) -> [PBXTextSpan] {
        var spans: [PBXTextSpan] = []
        var index = 0
        while index < bytes.count {
            let byte = bytes[index]
            switch byte {
            case UInt8(ascii: " "), UInt8(ascii: "\t"), UInt8(ascii: "\n"), UInt8(ascii: "\r"):
                index += 1
            case UInt8(ascii: "\""):
                let start = index
                index += 1
                while index < bytes.count, bytes[index] != UInt8(ascii: "\"") {
                    index += bytes[index] == UInt8(ascii: "\\") ? 2 : 1
                }
                guard index < bytes.count else {
                    throw .unsafeProject(path: path, why: "a quoted string is not closed")
                }
                index += 1
                spans.append(PBXTextSpan(kind: .string, range: start..<index))
            case UInt8(ascii: "/")
            where index + 1 < bytes.count && bytes[index + 1] == UInt8(ascii: "*"):
                index += 2
                while index + 1 < bytes.count,
                    !(bytes[index] == UInt8(ascii: "*") && bytes[index + 1] == UInt8(ascii: "/"))
                {
                    index += 1
                }
                guard index + 1 < bytes.count else {
                    throw .unsafeProject(path: path, why: "a comment is not closed")
                }
                index += 2
            case UInt8(ascii: "/")
            where index + 1 < bytes.count && bytes[index + 1] == UInt8(ascii: "/"):
                while index < bytes.count, bytes[index] != UInt8(ascii: "\n") { index += 1 }
            case UInt8(ascii: "{"), UInt8(ascii: "}"), UInt8(ascii: "("), UInt8(ascii: ")"),
                UInt8(ascii: "="), UInt8(ascii: ";"), UInt8(ascii: ","):
                spans.append(PBXTextSpan(kind: .punctuation, range: index..<(index + 1)))
                index += 1
            default:
                guard isWordByte(byte) else {
                    throw .unsafeProject(
                        path: path, why: "the text holds a byte that is not allowed")
                }
                let start = index
                while index < bytes.count, isWordByte(bytes[index]) { index += 1 }
                spans.append(PBXTextSpan(kind: .word, range: start..<index))
            }
        }
        return spans
    }

    private static func entries(
        spans: [PBXTextSpan], closers: [Int: Int], bytes: [UInt8], at open: Int, path: String
    ) throws(DomainError) -> [Entry] {
        guard let close = closers[open] else {
            throw .unsafeProject(path: path, why: "a dictionary is not closed")
        }
        var result: [Entry] = []
        var index = open + 1
        while index < close {
            guard index + 3 < spans.count, spans[index].kind != .punctuation,
                isOpen(spans, bytes, index + 1, "=")
            else { throw .unsafeProject(path: path, why: "a dictionary entry is not key = value;") }
            let first = index + 2
            let last = spans[first].kind == .punctuation ? (closers[first] ?? first) : first
            guard last + 1 <= close, isOpen(spans, bytes, last + 1, ";") else {
                throw .unsafeProject(
                    path: path, why: "a dictionary entry does not end with a semicolon")
            }
            let keySpan = spans[index]
            result.append(
                Entry(
                    key: Self.unquote(bytes, keySpan), keyIndex: index, valueFirst: first,
                    valueLast: last))
            index = last + 2
        }
        return result
    }

    private static func unquote(_ bytes: [UInt8], _ span: PBXTextSpan) -> String {
        let slice = bytes[span.range]
        guard span.kind == .string else { return String(decoding: slice, as: UTF8.self) }
        var result: [UInt8] = []
        var escaped = false
        for byte in slice.dropFirst().dropLast() {
            if !escaped, byte == UInt8(ascii: "\\") { escaped = true; continue }
            escaped = false
            result.append(byte)
        }
        return String(decoding: result, as: UTF8.self)
    }

    /// The text of a span. A quoted string is given without its quotes and escapes.
    func text(_ index: Int) -> String { Self.unquote(bytes, spans[index]) }

    /// The entries of the dictionary that opens at a span index.
    func entries(ofDictionaryAt open: Int) throws(DomainError) -> [Entry] {
        try Self.entries(spans: spans, closers: closers, bytes: bytes, at: open, path: path)
    }

    /// The entry of an object in the `objects` table. Its value is the object dictionary.
    func object(_ id: String) -> Entry? { objectEntries[id] }

    /// The entry with a key inside the dictionary that opens at a span index.
    func entry(_ key: String, inDictionaryAt open: Int) throws(DomainError) -> Entry? {
        try entries(ofDictionaryAt: open).first { $0.key == key }
    }

    /// The index of the span that closes the bracket opened at `open`.
    func close(of open: Int) -> Int? { closers[open] }

    /// The span indexes that start each item of the list that opens at a span index.
    func itemStarts(ofListAt open: Int) throws(DomainError) -> [Int] {
        guard let close = closers[open], Self.isOpen(spans, bytes, open, "(") else {
            throw .unsafeProject(path: path, why: "a list is not closed")
        }
        var result: [Int] = []
        var index = open + 1
        while index < close {
            result.append(index)
            let last = spans[index].kind == .punctuation ? (closers[index] ?? index) : index
            guard last + 1 <= close, Self.isOpen(spans, bytes, last + 1, ",") else {
                throw .unsafeProject(path: path, why: "a list item does not end with a comma")
            }
            index = last + 2
        }
        return result
    }

    /// The byte offset where the line that holds `offset` starts.
    func lineStart(of offset: Int) -> Int {
        var index = offset
        while index > 0, bytes[index - 1] != UInt8(ascii: "\n") { index -= 1 }
        return index
    }

    /// The byte offset after the line break that ends the line holding `offset`.
    func lineEnd(of offset: Int) -> Int {
        var index = offset
        while index < bytes.count, bytes[index] != UInt8(ascii: "\n") { index += 1 }
        return min(index + 1, bytes.count)
    }

    /// The tabs before a span when they are all that stands before it on its line, otherwise `nil`.
    func tabsBefore(span index: Int) -> String? {
        let offset = spans[index].range.lowerBound
        let prefix = bytes[lineStart(of: offset)..<offset]
        guard prefix.allSatisfy({ $0 == UInt8(ascii: "\t") }) else { return nil }
        return String(repeating: "\t", count: prefix.count)
    }

    /// A `/* Begin X section */` and `/* End X section */` pair, as the byte offsets of the two lines.
    struct Section {
        let isa: String
        let begin: Int
        let end: Int
    }

    /// The sections of the objects table in file order.
    func sections() -> [Section] {
        var result: [Section] = []
        var open: (isa: String, begin: Int)?
        var lineStartOffset = 0
        while lineStartOffset < bytes.count {
            let next = lineEnd(of: lineStartOffset)
            let line = String(decoding: bytes[lineStartOffset..<next], as: UTF8.self)
                .trimmingCharacters(in: .newlines)
            if line.hasPrefix("/* Begin "), line.hasSuffix(" section */") {
                open = (String(line.dropFirst(9).dropLast(11)), lineStartOffset)
            } else if line.hasPrefix("/* End "), line.hasSuffix(" section */"),
                let started = open, started.isa == String(line.dropFirst(7).dropLast(11))
            {
                result.append(Section(isa: started.isa, begin: started.begin, end: lineStartOffset))
                open = nil
            }
            lineStartOffset = next
        }
        return result
    }
}
