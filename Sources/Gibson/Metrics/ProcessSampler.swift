import Darwin
import Foundation

/// Reads the process table through sysctl and enriches it with task info.
/// Task info is only readable for processes the saver's own user owns, which is
/// exactly what we want to show anyway.
final class ProcessSampler {
    private struct Previous {
        var cpuTime: UInt64
        var at: Date
    }

    private var history: [Int32: Previous] = [:]
    private var userNames: [uid_t: String] = [:]

    struct Result {
        var rows: [MetricsSnapshot.Process] = []
        var processCount = 0
        var threadCount = 0
    }

    func sample(limit: Int) -> Result {
        var result = Result()
        guard let table = processTable() else { return result }
        result.processCount = table.count

        let now = Date()
        var rows: [MetricsSnapshot.Process] = []
        rows.reserveCapacity(table.count)
        var seen = Set<Int32>()

        for entry in table {
            let pid = entry.kp_proc.p_pid
            guard pid > 0 else { continue }
            seen.insert(pid)

            var info = proc_taskinfo()
            let expected = Int32(MemoryLayout<proc_taskinfo>.stride)
            guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, expected) == expected else { continue }

            let cpuTime = info.pti_total_user &+ info.pti_total_system
            var cpu = 0.0
            if let previous = history[pid] {
                let elapsed = now.timeIntervalSince(previous.at)
                if elapsed > 0, cpuTime >= previous.cpuTime {
                    cpu = Double(cpuTime - previous.cpuTime) / 1_000_000_000 / elapsed * 100
                }
            }
            history[pid] = Previous(cpuTime: cpuTime, at: now)
            result.threadCount += Int(info.pti_threadnum)

            let started = Date(timeIntervalSince1970:
                Double(entry.kp_proc.p_un.__p_starttime.tv_sec)
                    + Double(entry.kp_proc.p_un.__p_starttime.tv_usec) / 1_000_000)

            rows.append(MetricsSnapshot.Process(
                pid: pid,
                user: userName(for: entry.kp_eproc.e_ucred.cr_uid),
                command: "",
                cpu: min(cpu, 999),
                memory: info.pti_resident_size,
                threads: Int(info.pti_threadnum),
                started: started
            ))
        }

        history = history.filter { seen.contains($0.key) }

        let hasCPUData = rows.contains { $0.cpu > 0 }
        rows.sort { lhs, rhs in
            hasCPUData ? lhs.cpu > rhs.cpu : lhs.memory > rhs.memory
        }
        result.rows = Array(rows.prefix(limit))

        // Resolving a name is a syscall per process, and the sort only cares
        // about CPU and memory, so only the rows that survived it pay.
        var wanted: [Int32: Int] = [:]
        wanted.reserveCapacity(result.rows.count)
        for (index, row) in result.rows.enumerated() { wanted[row.pid] = index }
        for entry in table {
            guard let index = wanted[entry.kp_proc.p_pid] else { continue }
            result.rows[index].command = commandName(pid: entry.kp_proc.p_pid, entry: entry)
        }
        return result
    }

    private func processTable() -> [kinfo_proc]? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        for _ in 0 ..< 3 {
            var size = 0
            guard sysctl(&mib, 4, nil, &size, nil, 0) == 0, size > 0 else { return nil }
            // The table can grow between the two calls, so ask for some slack.
            size += size / 8
            let count = size / MemoryLayout<kinfo_proc>.stride
            var buffer = [kinfo_proc](repeating: kinfo_proc(), count: count)
            var written = 0
            let status = buffer.withUnsafeMutableBytes { raw -> Int32 in
                var length = raw.count
                let result = sysctl(&mib, 4, raw.baseAddress, &length, nil, 0)
                written = length
                return result
            }
            // Use the length this call reported, not a fresh size query: the
            // table can shrink in between and leave zeroed entries in the tail.
            if status == 0 {
                return Array(buffer.prefix(written / MemoryLayout<kinfo_proc>.stride))
            }
            if errno != ENOMEM { return nil }
        }
        return nil
    }

    private func commandName(pid: Int32, entry: kinfo_proc) -> String {
        var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        if proc_pidpath(pid, &path, UInt32(path.count)) > 0 {
            let full = String(cString: path)
            if !full.isEmpty {
                return (full as NSString).lastPathComponent
            }
        }
        let comm = entry.kp_proc.p_comm
        return withUnsafeBytes(of: comm) { raw in
            guard let base = raw.baseAddress else { return "" }
            return String(cString: base.assumingMemoryBound(to: CChar.self))
        }
    }

    private func userName(for uid: uid_t) -> String {
        if let cached = userNames[uid] { return cached }
        var name = String(uid)
        if let entry = getpwuid(uid), let raw = entry.pointee.pw_name {
            name = String(cString: raw)
        }
        userNames[uid] = name
        return name
    }
}
