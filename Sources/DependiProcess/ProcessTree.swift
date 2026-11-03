import Darwin
import Foundation

/// Finds and kills a process and everything below it.
enum ProcessTree {
    /// Returns the ids of every descendant of a process, found in the process table.
    static func descendants(of root: pid_t) -> [pid_t] {
        let capacity = Int(proc_listallpids(nil, 0))
        guard capacity > 0 else { return [] }
        var all = [pid_t](repeating: 0, count: capacity + 64)
        let bytes = Int32(all.count * MemoryLayout<pid_t>.size)
        let filled = Int(proc_listallpids(&all, bytes))
        guard filled > 0 else { return [] }
        var childrenByParent: [pid_t: [pid_t]] = [:]
        for pid in all.prefix(filled) where pid > 0 {
            var info = proc_bsdinfo()
            let size = Int32(MemoryLayout<proc_bsdinfo>.size)
            guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { continue }
            childrenByParent[pid_t(info.pbi_ppid), default: []].append(pid)
        }
        var found: [pid_t] = []
        var queue = childrenByParent[root] ?? []
        while let next = queue.first {
            queue.removeFirst()
            found.append(next)
            queue.append(contentsOf: childrenByParent[next] ?? [])
        }
        return found
    }

    /// Kills the process group and every descendant. A test helper can leave the group.
    static func kill(root: pid_t) {
        for _ in 0..<2 {
            let known = descendants(of: root)
            _ = Darwin.kill(-root, SIGKILL)
            _ = Darwin.kill(root, SIGKILL)
            for pid in known { _ = Darwin.kill(pid, SIGKILL) }
        }
    }
}
