import Darwin
import Foundation

/// Keeps the live child process groups and kills them all when asked.
///
/// A signal to Dependi does not reach its children, because each child leads its own process group.
/// The executable calls `terminateAll` from its signal handler.
public final class ChildProcessRegistry: ChildProcessTracking, @unchecked Sendable {
    private let lock = NSLock()
    private var live: Set<pid_t> = []
    private var isTerminating = false
    private let terminate: @Sendable (pid_t) -> Void

    /// Creates a registry that kills a child group and everything below it.
    public convenience init() {
        self.init(terminate: { ProcessTree.kill(root: $0) })
    }

    init(terminate: @escaping @Sendable (pid_t) -> Void) {
        self.terminate = terminate
    }

    /// The number of children that are alive.
    var liveCount: Int { lock.withLock { live.count } }

    /// Records a child. After `terminateAll`, a new child is killed at once.
    public func started(_ pid: pid_t) {
        lock.withLock {
            live.insert(pid)
            if isTerminating { terminate(pid) }
        }
    }

    /// Forgets a child. It waits for a running `terminateAll`, so no kill reaches a reaped child.
    public func finished(_ pid: pid_t) {
        lock.withLock { _ = live.remove(pid) }
    }

    /// Kills every live child group, and every child that starts later.
    public func terminateAll() {
        lock.withLock {
            isTerminating = true
            for pid in live { terminate(pid) }
        }
    }
}
