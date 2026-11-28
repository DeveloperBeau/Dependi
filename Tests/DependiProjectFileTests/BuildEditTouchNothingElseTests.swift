import Foundation
import Testing

@Suite("Project file editor touches nothing else", .timeLimit(.minutes(1)))
struct BuildEditTouchNothingElseTests {
    @Test("every original line survives and only lines are added", arguments: EditCase.all)
    func onlyAddedLines(_ item: EditCase) throws {
        let world = try EditWorld(item.fixture)
        try world.configure(target: item.target, bundle: item.bundle)
        let before = String(decoding: world.original, as: UTF8.self)
        let added = assertOnlyAdded(before: before, after: try world.currentText())
        #expect(!added.isEmpty)
        let ordered = added.filter {
            $0.contains("= {isa = PBX") || $0.contains("ENABLE_USER_SCRIPT_SANDBOXING")
                || $0.contains("/* Dependi */ = {")
        }
        assertSortedAmongSiblings(in: try world.currentText(), lines: ordered)
        #expect(
            added.allSatisfy {
                !$0.contains("ENABLE_USER_SCRIPT_SANDBOXING") || $0.hasSuffix("= NO;")
            })
    }

    @Test("ids and comments of the original file stay in the edited file", arguments: EditCase.all)
    func idsAndCommentsStay(_ item: EditCase) throws {
        let world = try EditWorld(item.fixture)
        try world.configure(target: item.target, bundle: item.bundle)
        let before = String(decoding: world.original, as: UTF8.self)
        let after = try world.currentText()
        let pattern = try NSRegularExpression(pattern: #"[0-9A-Fa-f_OBJ]{5,24} /\* [^*]* \*/"#)
        let range = NSRange(before.startIndex..., in: before)
        var missing = 0
        var count = 0
        pattern.enumerateMatches(in: before, range: range) { match, _, _ in
            guard let match, let found = Range(match.range, in: before) else { return }
            count += 1
            if !after.contains(before[found]) { missing += 1 }
        }
        #expect(count > 50)
        #expect(missing == 0)
    }
}
