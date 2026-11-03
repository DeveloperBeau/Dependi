import DependiInit
import Testing

@Suite("Init outcome")
struct InitOutcomeTests {
    @Test("outcomes compare by case and by reason")
    func outcomesCompare() {
        #expect(InitOutcome.installed == InitOutcome.installed)
        #expect(InitOutcome.stopped(reason: "a") != InitOutcome.stopped(reason: "b"))
        #expect(InitOutcome.reported != InitOutcome.installed)
    }
}
