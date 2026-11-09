import Darwin

/// A failed wait on a child. The code is the `errno` value.
struct WaitFailure: Error, Equatable {
    let code: Int32
}

/// Looks at a child and reaps it. A wait can fail, for example when something else reaped the child.
enum ChildWait {
    /// What a look at a child found.
    enum State: Equatable {
        case running
        case exited
        case failed(Int32)
    }

    /// Tells whether the child has exited. It does not reap, so the process id stays reserved
    /// and a later signal cannot hit another process that reused it.
    static func state(of pid: pid_t) -> State {
        var info = siginfo_t()
        while true {
            info.si_pid = 0
            if waitid(P_PID, id_t(pid), &info, WEXITED | WNOHANG | WNOWAIT) == 0 {
                return info.si_pid == pid ? .exited : .running
            }
            if errno != EINTR { return .failed(errno) }
        }
    }

    /// Reaps the child and returns its wait status. It blocks until the child has exited.
    static func reap(_ pid: pid_t) -> Result<Int32, WaitFailure> {
        var status: Int32 = 0
        while true {
            if waitpid(pid, &status, 0) == pid { return .success(status) }
            if errno != EINTR { return .failure(WaitFailure(code: errno)) }
        }
    }
}
