import DependiDomain
import DependiTestSupport
import Foundation
import Testing

@testable import DependiComposition

@Suite("Run deadline")
struct DeadlineProcessRunnerTests {
    private let ok = Result<ProcessOutput, DomainError>.success(
        ProcessOutput(exitStatus: 0, standardOutput: Data(), standardError: Data()))

    private func request(_ seconds: Double, name: String = "/bin/tool") -> ProcessRequest {
        ProcessRequest(
            executable: name, arguments: ["a", "b"], environment: ["K": "V"],
            workingDirectory: "/w", timeoutSeconds: seconds, maximumOutputBytes: 99)
    }

    private func make(limit: Double, clock: LockedBox<Double>, results: Int = 5) -> (
        DeadlineProcessRunner, FakeProcessRunner
    ) {
        let fake = FakeProcessRunner(results: Array(repeating: ok, count: results))
        let runner = DeadlineProcessRunner(
            wrapping: fake, limitSeconds: limit, now: { clock.withValue { $0 } })
        return (runner, fake)
    }

    @Test("a spawn inside the run time passes through with the request unchanged")
    func insideTheLimit() throws {
        let clock = LockedBox(100.0)
        let (runner, fake) = make(limit: 300, clock: clock)
        clock.withValue { $0 = 150 }
        _ = try runner.run(request(60))
        #expect(fake.requests == [request(60)])
    }

    @Test("a child gets no more time than the run has left")
    func childTimeIsClamped() throws {
        let clock = LockedBox(0.0)
        let (runner, fake) = make(limit: 100, clock: clock)
        clock.withValue { $0 = 70 }
        _ = try runner.run(request(60))
        #expect(fake.requests.map(\.timeoutSeconds) == [30])
        #expect(fake.requests.first?.arguments == ["a", "b"])
        #expect(fake.requests.first?.workingDirectory == "/w")
        #expect(fake.requests.first?.maximumOutputBytes == 99)
    }

    @Test("a spawn after the run time is used up fails and starts nothing")
    func afterTheLimit() {
        let clock = LockedBox(0.0)
        let (runner, fake) = make(limit: 300, clock: clock)
        clock.withValue { $0 = 300 }
        let expected = DomainError.processFailed(
            command: "/bin/tool a b",
            reason:
                "the run took longer than runTimeoutSeconds (300 seconds), so no more processes start"
        )
        #expect(throws: expected) { try runner.run(request(60)) }
        #expect(fake.requests.isEmpty)
    }

    @Test("many slow packages stop the run at the limit and not after the last package")
    func serialPackagesHitTheLimit() {
        let clock = LockedBox(0.0)
        let (runner, fake) = make(limit: 100, clock: clock, results: 20)
        var started = 0
        for _ in 0..<20 {
            do {
                _ = try runner.run(request(60))
                started += 1
                clock.withValue { $0 += 45 }
            } catch { break }
        }
        // 0 s, 45 s and 90 s start. At 135 s the limit is gone.
        #expect(started == 3)
        #expect(fake.requests.map(\.timeoutSeconds) == [60, 55, 10])
    }

    @Test("the first spawn at the start of the run is allowed even with a short limit")
    func firstSpawn() throws {
        let clock = LockedBox(5.0)
        let (runner, fake) = make(limit: 0.5, clock: clock)
        _ = try runner.run(request(60))
        #expect(fake.requests.map(\.timeoutSeconds) == [0.5])
    }

    @Test("an error of the wrapped runner passes through")
    func innerErrorPasses() {
        let clock = LockedBox(0.0)
        let failure = DomainError.processFailed(command: "x", reason: "boom")
        let fake = FakeProcessRunner(results: [.failure(failure)])
        let runner = DeadlineProcessRunner(
            wrapping: fake, limitSeconds: 10, now: { clock.withValue { $0 } })
        #expect(throws: failure) { try runner.run(request(5)) }
    }
}
