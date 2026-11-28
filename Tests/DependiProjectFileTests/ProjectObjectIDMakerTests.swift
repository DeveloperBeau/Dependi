import Foundation
import Testing

@testable import DependiProjectFile

@Suite("Project object ids", .timeLimit(.minutes(1)))
struct ProjectObjectIDMakerTests {
    @Test("an id is 24 upper case hex digits")
    func shape() {
        var maker = ProjectObjectIDMaker(existingText: "")
        let id = maker.make(targetID: "T", role: "buildFile")
        #expect(id.count == 24)
        #expect(id.allSatisfy { "0123456789ABCDEF".contains($0) })
    }

    @Test("the same input gives the same id and another role gives another id")
    func repeatable() {
        var first = ProjectObjectIDMaker(existingText: "")
        var second = ProjectObjectIDMaker(existingText: "")
        var otherRole = ProjectObjectIDMaker(existingText: "")
        var otherTarget = ProjectObjectIDMaker(existingText: "")
        let id = first.make(targetID: "T", role: "buildFile")
        #expect(second.make(targetID: "T", role: "buildFile") == id)
        #expect(otherRole.make(targetID: "T", role: "fileReference") != id)
        #expect(otherTarget.make(targetID: "U", role: "buildFile") != id)
    }

    @Test("an id that is in the project text is skipped, even inside a comment")
    func collisionWithText() {
        var probe = ProjectObjectIDMaker(existingText: "")
        let taken = probe.make(targetID: "T", role: "buildFile")
        for text in ["\t\t\(taken) /* x */ = {", "/* \(taken) */"] {
            var maker = ProjectObjectIDMaker(existingText: text)
            let id = maker.make(targetID: "T", role: "buildFile")
            #expect(id != taken)
            #expect(id.count == 24)
        }
    }

    @Test("an id that was made earlier in the run is not made again")
    func collisionWithEarlierID() {
        var maker = ProjectObjectIDMaker(existingText: "")
        let first = maker.make(targetID: "T", role: "buildFile")
        let second = maker.make(targetID: "T", role: "buildFile")
        #expect(first != second)
    }
}
