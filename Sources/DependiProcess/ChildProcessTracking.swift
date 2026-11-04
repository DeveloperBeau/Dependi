import Darwin

/// Learns which child processes are alive, so that a signal handler can stop them.
public protocol ChildProcessTracking: Sendable {
    /// Records a child that was just started. The child leads its own process group.
    func started(_ pid: pid_t)

    /// Forgets a child. The runner calls it before it reaps the child.
    func finished(_ pid: pid_t)
}
