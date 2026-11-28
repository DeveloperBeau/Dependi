import DependiDomain
import Foundation
import Testing

@testable import DependiProjectFile

@Suite("Project object ids", .timeLimit(.minutes(1)))
struct ProjectObjectIDMakerTests {
    private func made(_ maker: inout ProjectObjectIDMaker, _ target: String, _ role: String) throws
        -> String
    {
        let id = maker.make(targetID: target, role: role)
        return try #require(id)
    }

    @Test("an id is 24 upper case hex digits")
    func shape() throws {
        var maker = ProjectObjectIDMaker(existingText: "")
        let id = try made(&maker, "T", "buildFile")
        #expect(id.count == 24)
        #expect(id.allSatisfy { "0123456789ABCDEF".contains($0) })
    }

    @Test("the same input gives the same id and another role gives another id")
    func repeatable() throws {
        var first = ProjectObjectIDMaker(existingText: "")
        var second = ProjectObjectIDMaker(existingText: "")
        var otherRole = ProjectObjectIDMaker(existingText: "")
        var otherTarget = ProjectObjectIDMaker(existingText: "")
        let id = try made(&first, "T", "buildFile")
        #expect(second.make(targetID: "T", role: "buildFile") == id)
        #expect(otherRole.make(targetID: "T", role: "fileReference") != id)
        #expect(otherTarget.make(targetID: "U", role: "buildFile") != id)
    }

    @Test("an id that is in the project text is skipped, even inside a comment")
    func collisionWithText() throws {
        var probe = ProjectObjectIDMaker(existingText: "")
        let taken = try made(&probe, "T", "buildFile")
        for text in ["\t\t\(taken) /* x */ = {", "/* \(taken) */"] {
            var maker = ProjectObjectIDMaker(existingText: text)
            let id = try made(&maker, "T", "buildFile")
            #expect(id != taken)
            #expect(id.count == 24)
        }
    }

    @Test("an id that was made earlier in the run is not made again")
    func collisionWithEarlierID() throws {
        var maker = ProjectObjectIDMaker(existingText: "")
        let first = try made(&maker, "T", "buildFile")
        let second = try made(&maker, "T", "buildFile")
        #expect(first != second)
    }

    @Test("a search that finds only clashes stops after the attempt limit with no id")
    func attemptLimit() {
        // The ids for counters 0 and 1 are written by hand.
        let first = "FBC7677AA8258D63F427E5C4"
        let second = "ABFD96C1C4081B56F95F1DC4"
        var short = ProjectObjectIDMaker(existingText: first, attemptLimit: 1)
        #expect(short.make(targetID: "T", role: "buildFile") == nil)
        var enough = ProjectObjectIDMaker(existingText: first, attemptLimit: 2)
        #expect(enough.make(targetID: "T", role: "buildFile") == second)
        var bothTaken = ProjectObjectIDMaker(existingText: first + second, attemptLimit: 2)
        #expect(bothTaken.make(targetID: "T", role: "buildFile") == nil)
    }

    @Test("the planner refuses when no free id is found and says which id it needed")
    func plannerRefusesWithoutFreeID() throws {
        let data = FixtureWorld.fixture("old-format-mew")
        let model = try ProjectModel.parse(data, path: "/p/project.pbxproj", folder: "/p")
        let scanner = try PBXTextScanner(bytes: Array(data), path: "/p/project.pbxproj")
        // The first id for the file reference of MewTestsApp is written by hand.
        let text = String(decoding: data, as: UTF8.self) + "\n3F3B65923D016048D4FAF971"
        var planner = BuildSetupPlanner(
            model: model, scanner: scanner,
            ids: ProjectObjectIDMaker(existingText: text, attemptLimit: 1))
        #expect(
            throws: DomainError.fileUnreadable(
                path: "/p/project.pbxproj",
                reason:
                    "Dependi cannot edit this project file safely: no free object id was found for the fileReference of MewTestsApp"
            )
        ) { try planner.plan(targetName: "MewTestsApp", bundlePath: "/p/Settings.bundle") }
    }
}
