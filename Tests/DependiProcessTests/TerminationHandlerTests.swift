import Darwin
import Foundation
import Testing

@testable import DependiProcess

@Suite(.serialized, .timeLimit(.minutes(1)))
struct TerminationHandlerTests {
    private final class Received: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [Int32] = []
        let semaphore = DispatchSemaphore(value: 0)
        func add(_ value: Int32) {
            lock.withLock { values.append(value) }
            semaphore.signal()
        }
        var all: [Int32] { lock.withLock { values } }
    }

    @Test func aWatchedSignalCallsTheHandlerWithItsNumber() {
        let received = Received()
        let handler = TerminationHandler(signals: [SIGUSR2]) { received.add($0) }
        handler.start()
        defer { handler.stop() }
        kill(getpid(), SIGUSR2)
        #expect(received.semaphore.wait(timeout: .now() + 5) == .success)
        #expect(received.all == [SIGUSR2])
    }

    @Test func eachWatchedSignalIsReportedUnderItsOwnNumber() {
        let received = Received()
        let handler = TerminationHandler(signals: [SIGUSR1, SIGUSR2]) { received.add($0) }
        handler.start()
        defer { handler.stop() }
        kill(getpid(), SIGUSR1)
        #expect(received.semaphore.wait(timeout: .now() + 5) == .success)
        kill(getpid(), SIGUSR2)
        #expect(received.semaphore.wait(timeout: .now() + 5) == .success)
        #expect(received.all == [SIGUSR1, SIGUSR2])
    }

    @Test func aSignalThatIsNotWatchedDoesNotCallTheHandler() {
        let received = Received()
        let other = TerminationHandler(signals: [SIGUSR1]) { _ in }
        other.start()
        defer { other.stop() }
        let handler = TerminationHandler(signals: [SIGUSR2]) { received.add($0) }
        handler.start()
        defer { handler.stop() }
        kill(getpid(), SIGUSR1)
        #expect(received.semaphore.wait(timeout: .now() + 0.3) == .timedOut)
        #expect(received.all.isEmpty)
    }
}
