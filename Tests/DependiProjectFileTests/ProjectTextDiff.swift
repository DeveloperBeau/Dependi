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
