import Darwin
import DependiDomain
import Foundation
import Testing

@testable import DependiProcess

/// Records what the runner tells it, and looks at the child each time it is told.
private final class RecordingTracker: ChildProcessTracking, @unchecked Sendable {
    private let lock = NSLock()
    private var events: [String] = []
    private var pids: [pid_t] = []
    private var unreapedAtFinish: [Bool] = []

    func started(_ pid: pid_t) {
        lock.withLock {
            events.append("started")
            pids.append(pid)
        }
    }

    func finished(_ pid: pid_t) {
        let state = ChildWait.state(of: pid)
        lock.withLock {
            events.append("finished")
            unreapedAtFinish.append(state != .failed(ECHILD))
        }
    }

    var recorded: [String] { lock.withLock { events } }
    var allUnreapedAtFinish: Bool { lock.withLock { unreapedAtFinish.allSatisfy { $0 } } }
    var firstPid: pid_t? { lock.withLock { pids.first } }
}

private func shell(_ script: String, timeout: Double = 30) -> ProcessRequest {
    ProcessRequest(
        executable: "/bin/sh", arguments: ["-c", script], environment: ["PATH": "/usr/bin:/bin"],
        workingDirectory: nil, timeoutSeconds: timeout, maximumOutputBytes: 1_000_000)
}

/// Starts a program directly, so that nobody reaps it before the test does.
private func spawnDirect(_ script: String) -> pid_t {
    var pid: pid_t = 0
    let arguments: [UnsafeMutablePointer<CChar>?] = [
        strdup("sh"), strdup("-c"), strdup(script), nil,
    ]
    defer { for pointer in arguments { free(pointer) } }
    let code = posix_spawn(&pid, "/bin/sh", nil, nil, arguments, nil)
    precondition(code == 0)
    return pid
}

@Suite(.serialized)
struct ProcessLifecycleTests {
    // MARK: Waiting

    @Test func aLookAtAnExitedChildDoesNotReapIt() {
        let pid = spawnDirect("exit 7")
        var state = ChildWait.state(of: pid)
        for _ in 0..<200 where state == .running {
            usleep(25_000)
            state = ChildWait.state(of: pid)
        }
        #expect(state == .exited)
        #expect(ChildWait.state(of: pid) == .exited)
        let reaped = ChildWait.reap(pid)
        #expect(reaped == .success(7 << 8))
        #expect(ChildWait.state(of: pid) == .failed(ECHILD))
    }

    @Test func aRunningChildIsReportedAsRunning() {
        let pid = spawnDirect("sleep 30")
        #expect(ChildWait.state(of: pid) == .running)
        kill(pid, SIGKILL)
        #expect(ChildWait.reap(pid) == .success(SIGKILL))
    }

    @Test func aProcessThatIsNotOurChildFailsTheWaitInsteadOfReportingSuccess() {
        // Process 1 is never a child of the test process.
        #expect(ChildWait.state(of: 1) == .failed(ECHILD))
        #expect(ChildWait.reap(1) == .failure(WaitFailure(code: ECHILD)))
    }

    // MARK: Tracking

    @Test func theRunnerTellsTheTrackerAboutStartAndFinishAndNothingMore() throws {
        let tracker = RecordingTracker()
        let runner = SystemProcessRunner(children: tracker)
        _ = try runner.run(shell("exit 0"))
        #expect(tracker.recorded == ["started", "finished"])
        #expect(tracker.allUnreapedAtFinish)
    }

    @Test func aTimedOutChildIsFinishedBeforeItIsReaped() {
        let tracker = RecordingTracker()
        let runner = SystemProcessRunner(children: tracker)
        #expect(throws: DomainError.self) { try runner.run(shell("sleep 30", timeout: 0.3)) }
        #expect(tracker.recorded == ["started", "finished"])
        #expect(tracker.allUnreapedAtFinish)
        if let pid = tracker.firstPid { #expect(kill(pid, 0) == -1 && errno == ESRCH) }
    }

    @Test func aChildThatCannotStartIsNeverTracked() {
        let tracker = RecordingTracker()
        let runner = SystemProcessRunner(children: tracker)
        let request = ProcessRequest(
            executable: "/nonexistent/tool", arguments: [], environment: [:],
            workingDirectory: nil, timeoutSeconds: 5, maximumOutputBytes: 100)
        #expect(throws: DomainError.self) { try runner.run(request) }
        #expect(tracker.recorded.isEmpty)
    }

    // MARK: Registry

    @Test func terminateAllKillsEveryLiveChildAndNoFinishedOne() {
        let killed = Killed()
        let registry = ChildProcessRegistry(terminate: { killed.add($0) })
        registry.started(101)
        registry.started(102)
        registry.started(103)
        registry.finished(102)
        registry.terminateAll()
        #expect(killed.sorted == [101, 103])
        #expect(registry.liveCount == 2)
    }

    @Test func aChildThatStartsAfterTerminateAllIsKilledAtOnce() {
        let killed = Killed()
        let registry = ChildProcessRegistry(terminate: { killed.add($0) })
        registry.terminateAll()
        #expect(killed.sorted.isEmpty)
        registry.started(201)
        #expect(killed.sorted == [201])
    }

    @Test func terminateAllWithNoChildrenDoesNothing() {
        let killed = Killed()
        ChildProcessRegistry(terminate: { killed.add($0) }).terminateAll()
        #expect(killed.sorted.isEmpty)
    }

    @Test func aFinishedChildIsNotKilled() {
        let killed = Killed()
        let registry = ChildProcessRegistry(terminate: { killed.add($0) })
        registry.started(301)
        registry.finished(301)
        registry.terminateAll()
        #expect(killed.sorted.isEmpty)
    }

    @Test func terminateAllStopsARealRunningChildQuickly() throws {
        let registry = ChildProcessRegistry()
        let runner = SystemProcessRunner(children: registry)
        let done = DispatchSemaphore(value: 0)
        let result = ResultBox()
        DispatchQueue.global().async {
            result.set(Result { try runner.run(shell("sleep 30", timeout: 60)) })
            done.signal()
        }
        var waited = 0
        while registry.liveCount == 0 && waited < 200 {
            usleep(25_000)
            waited += 1
        }
        #expect(registry.liveCount == 1)
        let start = Date()
        registry.terminateAll()
        #expect(done.wait(timeout: .now() + 10) == .success)
        #expect(Date().timeIntervalSince(start) < 8)
        // The child died from SIGKILL, so the shell status is 128 + 9.
        #expect(try result.get().exitStatus == 137)
        #expect(registry.liveCount == 0)
    }
}

private final class Killed: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [pid_t] = []
    func add(_ pid: pid_t) { lock.withLock { values.append(pid) } }
    var sorted: [pid_t] { lock.withLock { values.sorted() } }
}

private final class ResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Result<ProcessOutput, any Error>?
    func set(_ value: Result<ProcessOutput, any Error>) { lock.withLock { stored = value } }
    func get() throws -> ProcessOutput {
        try lock.withLock { stored }!.get()
    }
}

extension ProcessLifecycleTests {
    @Test(
        "a time limit that is not a finite positive number is refused before any process starts",
        arguments: [Double.nan, 0, -1, -0.001, .infinity, -.infinity, 604_800.5, 1e300])
    func invalidTimeLimit(seconds: Double) {
        let tracker = RecordingTracker()
        let runner = SystemProcessRunner(children: tracker)
        var request = shell("exit 0")
        request = ProcessRequest(
            executable: request.executable, arguments: request.arguments,
            environment: request.environment, workingDirectory: nil, timeoutSeconds: seconds,
            maximumOutputBytes: 100)
        #expect(
            throws: DomainError.processFailed(
                command: "/bin/sh -c exit 0",
                reason: "the time limit must be a number above 0 and at most one week")
        ) { try runner.run(request) }
        #expect(tracker.recorded.isEmpty)
    }

    @Test("the longest allowed limit still runs a child")
    func longestLimitWorks() throws {
        let runner = SystemProcessRunner(children: RecordingTracker())
        let output = try runner.run(shell("printf ok", timeout: 604_800))
        #expect(output.standardOutput == Data("ok".utf8))
    }
}
