import Darwin
import DependiDomain
import Foundation

/// Runs child processes with `posix_spawn`. Each child leads its own process group, so a time-out kills all of it.
public struct SystemProcessRunner: ProcessRunning {
    /// Creates a runner.
    public init() {}

    /// Runs a process to the end. It fails on a spawn error, a time-out or output over the limit.
    public func run(_ request: ProcessRequest) throws(DomainError) -> ProcessOutput {
        let command = ([request.executable] + request.arguments).joined(separator: " ")
        func failure(_ reason: String) -> DomainError {
            .processFailed(command: command, reason: reason)
        }

        var outPipe: [Int32] = [0, 0]
        var errPipe: [Int32] = [0, 0]
        guard pipe(&outPipe) == 0 else { throw failure("cannot create a pipe") }
        guard pipe(&errPipe) == 0 else {
            close(outPipe[0])
            close(outPipe[1])
            throw failure("cannot create a pipe")
        }
        let parentEnds = [outPipe[0], errPipe[0]]
        let childEnds = [outPipe[1], errPipe[1]]

        let spawned = spawn(request, standardOutput: outPipe[1], standardError: errPipe[1])
        for descriptor in childEnds { close(descriptor) }
        guard spawned.code == 0 else {
            for descriptor in parentEnds { close(descriptor) }
            throw failure("cannot start: \(String(cString: strerror(spawned.code)))")
        }
        let pid = spawned.pid

        let signals = RunSignals()
        let collectors = [
            StreamCollector(limit: request.maximumOutputBytes, signals: signals),
            StreamCollector(limit: request.maximumOutputBytes, signals: signals),
        ]
        let readers = DispatchGroup()
        for (collector, descriptor) in zip(collectors, parentEnds) {
            DispatchQueue.global().async(group: readers) { collector.drain(descriptor) }
        }
        defer {
            signals.stop()
            readers.wait()
            for descriptor in parentEnds { close(descriptor) }
        }

        let deadline = DispatchTime.now() + request.timeoutSeconds
        var status: Int32 = 0
        var exited = false
        while !exited {
            if signals.hasOverflowed { break }
            var waitStatus: Int32 = 0
            let result = waitpid(pid, &waitStatus, WNOHANG)
            if result == pid {
                status = waitStatus
                exited = true
            } else if result < 0 && errno != EINTR {
                exited = true
            } else if DispatchTime.now() >= deadline {
                abort(pid, exited: false)
                throw failure("timed out after \(Self.describe(request.timeoutSeconds)) seconds")
            } else {
                usleep(2_000)
            }
        }
        if signals.hasOverflowed {
            abort(pid, exited: exited)
            throw failure("output is over the limit of \(request.maximumOutputBytes) bytes")
        }
        if readers.wait(timeout: deadline) == .timedOut {
            abort(pid, exited: true)
            throw failure("timed out after \(Self.describe(request.timeoutSeconds)) seconds")
        }
        if signals.hasOverflowed {
            abort(pid, exited: true)
            throw failure("output is over the limit of \(request.maximumOutputBytes) bytes")
        }
        return ProcessOutput(
            exitStatus: Self.exitStatus(fromWaitStatus: status),
            standardOutput: collectors[0].data,
            standardError: collectors[1].data
        )
    }

    /// Kills the whole tree and reaps the child if it is still unreaped.
    private func abort(_ pid: pid_t, exited: Bool) {
        ProcessTree.kill(root: pid)
        if !exited {
            var ignored: Int32 = 0
            while waitpid(pid, &ignored, 0) < 0 && errno == EINTR {}
        }
    }

    private static func describe(_ seconds: Double) -> String {
        seconds == seconds.rounded() ? String(Int(seconds)) : String(seconds)
    }

    private static func exitStatus(fromWaitStatus status: Int32) -> Int32 {
        let signal = status & 0x7f
        return signal == 0 ? (status >> 8) & 0xff : 128 + signal
    }

    private func spawn(
        _ request: ProcessRequest,
        standardOutput: Int32,
        standardError: Int32
    ) -> (pid: pid_t, code: Int32) {
        var actions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        posix_spawn_file_actions_init(&actions)
        posix_spawnattr_init(&attributes)
        defer {
            posix_spawn_file_actions_destroy(&actions)
            posix_spawnattr_destroy(&attributes)
        }
        posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_adddup2(&actions, standardOutput, 1)
        posix_spawn_file_actions_adddup2(&actions, standardError, 2)
        if let directory = request.workingDirectory {
            let code = posix_spawn_file_actions_addchdir_np(&actions, directory)
            if code != 0 { return (0, code) }
        }
        // Reset signal handling, because the parent may ignore or block signals that the child needs.
        var allSignals = sigset_t()
        sigfillset(&allSignals)
        var noSignals = sigset_t()
        sigemptyset(&noSignals)
        posix_spawnattr_setsigdefault(&attributes, &allSignals)
        posix_spawnattr_setsigmask(&attributes, &noSignals)
        let flags =
            POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGDEF
            | POSIX_SPAWN_SETSIGMASK
        posix_spawnattr_setflags(&attributes, Int16(flags))
        posix_spawnattr_setpgroup(&attributes, 0)

        let argumentStrings = [request.executable] + request.arguments
        let environmentStrings = request.environment.map { "\($0.key)=\($0.value)" }
        var argv: [UnsafeMutablePointer<CChar>?] = argumentStrings.map { strdup($0) } + [nil]
        var envp: [UnsafeMutablePointer<CChar>?] = environmentStrings.map { strdup($0) } + [nil]
        defer {
            for pointer in argv { free(pointer) }
            for pointer in envp { free(pointer) }
        }
        var pid: pid_t = 0
        let code = posix_spawn(&pid, request.executable, &actions, &attributes, &argv, &envp)
        return (pid, code)
    }
}
