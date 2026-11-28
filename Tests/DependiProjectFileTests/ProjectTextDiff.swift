import Foundation
import Testing

/// Checks that an edit only added lines, apart from the lines it replaced on purpose.
///
/// Every original line must survive in order. The only lines that may go are the ones in `replaced`.
/// It returns the added lines in file order.
@discardableResult
func assertOnlyAdded(
    before: String, after: String, replaced: [String] = [],
    sourceLocation: SourceLocation = #_sourceLocation
) -> [String] {
    let old = before.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    let new = after.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    let difference = new.difference(from: old)
    var removed: [String] = []
    for case .remove(_, let line, _) in difference { removed.append(line) }
    #expect(
        removed.sorted() == replaced.sorted(), "removed lines: \(removed)",
        sourceLocation: sourceLocation)
    var added: [String] = []
    for case .insert(_, let line, _) in difference { added.append(line) }
    return added
}

/// Returns the text with one piece replaced. The piece must occur exactly `times` times.
func replacing(
    _ text: String, _ piece: String, with other: String, times: Int = 1,
    sourceLocation: SourceLocation = #_sourceLocation
) -> String {
    let count = text.components(separatedBy: piece).count - 1
    #expect(count == times, "the piece occurs \(count) times", sourceLocation: sourceLocation)
    return text.replacingOccurrences(of: piece, with: other)
}

/// Checks that each given line sits between sibling lines that sort around it.
///
/// A sibling is the nearest line above or below with the same tabs. The key of a line is its text up
/// to the first space, without quotes. Xcode keeps ids and build settings in byte order.
func assertSortedAmongSiblings(
    in text: String, lines wanted: [String], sourceLocation: SourceLocation = #_sourceLocation
) {
    let all = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    func tabs(_ line: String) -> Int { line.prefix { $0 == "\t" }.count }
    func key(_ line: String) -> String? {
        let body = line.drop { $0 == "\t" }
        guard let first = body.first, first.isLetter || first.isNumber || first == "\"" else {
            return nil
        }
        return String(body.prefix { $0 != " " }).replacingOccurrences(of: "\"", with: "")
    }
    func before(_ left: String, _ right: String) -> Bool {
        left.utf8.lexicographicallyPrecedes(right.utf8)
    }
    for (index, line) in all.enumerated() where wanted.contains(line) {
        guard let own = key(line) else { continue }
        let depth = tabs(line)
        var above = index - 1
        while above >= 0, tabs(all[above]) > depth || key(all[above]) == nil,
            tabs(all[above]) >= depth
        {
            above -= 1
        }
        var below = index + 1
        while below < all.count, tabs(all[below]) > depth || key(all[below]) == nil,
            tabs(all[below]) >= depth
        {
            below += 1
        }
        if above >= 0, tabs(all[above]) == depth, let other = key(all[above]) {
            #expect(
                !before(own, other), "\(own) sorts before \(other)", sourceLocation: sourceLocation)
        }
        if below < all.count, tabs(all[below]) == depth, let other = key(all[below]) {
            #expect(
                !before(other, own), "\(other) sorts before \(own)", sourceLocation: sourceLocation)
        }
    }
}
