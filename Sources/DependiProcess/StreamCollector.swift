import Darwin
import Foundation

/// Shared flags for one run. The readers and the waiting thread both use it.
final class RunSignals: @unchecked Sendable {
    private let lock = NSLock()
    private var overflowed = false
    private var stopped = false

    /// Whether a stream went over the byte limit.
    var hasOverflowed: Bool { lock.withLock { overflowed } }
    /// Whether the readers must stop at their next check.
    var isStopped: Bool { lock.withLock { stopped } }

    /// Records that a stream went over the byte limit.
    func markOverflow() { lock.withLock { overflowed = true } }
    /// Tells the readers to stop.
    func stop() { lock.withLock { stopped = true } }
}

/// Reads one pipe to its end and keeps at most a fixed number of bytes.
final class StreamCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()
    private let limit: Int
    private let signals: RunSignals

    init(limit: Int, signals: RunSignals) {
        self.limit = limit
        self.signals = signals
    }

    /// The bytes read so far.
    var data: Data { lock.withLock { buffer } }

    /// Reads from the descriptor until end of input, an overflow or a stop request.
    /// It polls so that a held-open pipe cannot block it forever.
    func drain(_ descriptor: Int32) {
        var chunk = [UInt8](repeating: 0, count: 65_536)
        while !signals.isStopped {
            var entry = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
            let ready = poll(&entry, 1, 50)
            if ready < 0 {
                if errno == EINTR { continue }
                return
            }
            if ready == 0 { continue }
            let count = read(descriptor, &chunk, chunk.count)
            if count < 0 {
                if errno == EINTR || errno == EAGAIN { continue }
                return
            }
            if count == 0 { return }
            if !append(chunk, count: count) { return }
        }
    }

    private func append(_ bytes: [UInt8], count: Int) -> Bool {
        lock.withLock {
            if buffer.count + count > limit {
                signals.markOverflow()
                return false
            }
            buffer.append(contentsOf: bytes[0..<count])
            return true
        }
    }
}
