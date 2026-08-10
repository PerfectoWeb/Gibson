import Darwin
import Foundation

// MARK: - CPU

/// Per core tick counters from the mach host. Deltas between two reads give
/// the utilisation for the interval.
final class CPUSampler {
    private var previous: [[UInt32]] = []

    struct Reading {
        var total: Double = 0
        var user: Double = 0
        var system: Double = 0
        var cores: [Double] = []
    }

    func sample() -> Reading {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0

        let status = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO,
                                         &cpuCount, &info, &infoCount)
        guard status == KERN_SUCCESS, let info else { return Reading() }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: info)),
                          vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }

        let states = Int(CPU_STATE_MAX)
        var current: [[UInt32]] = []
        current.reserveCapacity(Int(cpuCount))
        for core in 0 ..< Int(cpuCount) {
            let base = core * states
            current.append([
                UInt32(bitPattern: info[base + Int(CPU_STATE_USER)]),
                UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)]),
                UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)]),
                UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)])
            ])
        }

        defer { previous = current }
        guard previous.count == current.count else { return Reading() }

        var reading = Reading()
        var userTicks = 0.0
        var systemTicks = 0.0
        var totalTicks = 0.0

        for core in 0 ..< current.count {
            let deltas = (0 ..< 4).map { Double(current[core][$0] &- previous[core][$0]) }
            let busy = deltas[0] + deltas[1] + deltas[3]
            let all = busy + deltas[2]
            reading.cores.append(all > 0 ? busy / all * 100 : 0)
            userTicks += deltas[0] + deltas[3]
            systemTicks += deltas[1]
            totalTicks += all
        }

        if totalTicks > 0 {
            reading.user = userTicks / totalTicks * 100
            reading.system = systemTicks / totalTicks * 100
            reading.total = reading.user + reading.system
        }
        return reading
    }
}

// MARK: - Memory

enum MemorySampler {
    static func sample() -> MetricsSnapshot.Memory {
        var memory = MetricsSnapshot.Memory()
        memory.total = sysctlValue("hw.memsize") ?? 0

        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        let status = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard status == KERN_SUCCESS else { return memory }

        let page = UInt64(vm_kernel_page_size)
        memory.wired = UInt64(stats.wire_count) * page
        memory.compressed = UInt64(stats.compressor_page_count) * page
        memory.cached = UInt64(stats.external_page_count) * page
        let active = UInt64(stats.active_count) * page
        let inactive = UInt64(stats.inactive_count) * page

        // File backed pages are spread across both the active and the inactive
        // list, and can outnumber either of them on their own. These are
        // unsigned counters, so the subtraction has to be clamped or it traps.
        let resident = active + inactive
        let appMemory = resident > memory.cached ? resident - memory.cached : 0
        memory.used = memory.wired + memory.compressed + appMemory

        var swap = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.stride
        var mib: [Int32] = [CTL_VM, VM_SWAPUSAGE]
        if sysctl(&mib, 2, &swap, &swapSize, nil, 0) == 0 {
            memory.swapUsed = swap.xsu_used
            memory.swapTotal = swap.xsu_total
        }
        return memory
    }
}

// MARK: - Storage

enum StorageSampler {
    static func sample() -> [MetricsSnapshot.Volume] {
        let keys: [URLResourceKey] = [
            .volumeNameKey, .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey, .volumeIsBrowsableKey
        ]
        let mounted = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys,
            options: [.skipHiddenVolumes]
        ) ?? []

        var volumes: [MetricsSnapshot.Volume] = []
        for url in mounted {
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.volumeIsBrowsable == true,
                  let total = values.volumeTotalCapacity, total > 0
            else { continue }
            let free = values.volumeAvailableCapacityForImportantUsage ?? 0
            volumes.append(MetricsSnapshot.Volume(
                name: values.volumeName ?? url.lastPathComponent,
                total: UInt64(total),
                free: UInt64(max(0, free))
            ))
        }
        return volumes.sorted { $0.total > $1.total }
    }
}

// MARK: - Network

/// Byte counters from the link layer, differentiated over wall clock time.
final class NetworkSampler {
    private var lastIn: UInt64 = 0
    private var lastOut: UInt64 = 0
    private var lastTime = Date.distantPast

    func sample() -> MetricsSnapshot.Network {
        var result = MetricsSnapshot.Network()
        var totalIn: UInt64 = 0
        var totalOut: UInt64 = 0

        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return result }
        defer { freeifaddrs(head) }

        var address: String?
        var interface: String?

        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }
            let name = String(cString: entry.pointee.ifa_name)
            guard name != "lo0", let family = entry.pointee.ifa_addr?.pointee.sa_family else { continue }

            if family == UInt8(AF_LINK), let data = entry.pointee.ifa_data {
                let stats = data.assumingMemoryBound(to: if_data.self).pointee
                totalIn += UInt64(stats.ifi_ibytes)
                totalOut += UInt64(stats.ifi_obytes)
            }

            if family == UInt8(AF_INET), address == nil, entry.pointee.ifa_addr != nil {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                let length = socklen_t(MemoryLayout<sockaddr_in>.size)
                if getnameinfo(entry.pointee.ifa_addr, length, &host, socklen_t(host.count),
                               nil, 0, NI_NUMERICHOST) == 0 {
                    address = String(cString: host)
                    interface = name
                }
            }
        }

        result.totalIn = totalIn
        result.totalOut = totalOut
        result.address = address ?? "0.0.0.0"
        result.interface = interface ?? "en0"

        let now = Date()
        let elapsed = now.timeIntervalSince(lastTime)
        if elapsed > 0, elapsed < 30, totalIn >= lastIn, totalOut >= lastOut {
            result.downBytesPerSecond = Double(totalIn - lastIn) / elapsed
            result.upBytesPerSecond = Double(totalOut - lastOut) / elapsed
        }
        lastIn = totalIn
        lastOut = totalOut
        lastTime = now
        return result
    }
}

// MARK: - Host

enum HostSampler {
    static func hostName() -> String {
        var buffer = [CChar](repeating: 0, count: 256)
        if gethostname(&buffer, buffer.count) == 0 {
            let name = String(cString: buffer)
            return name.replacingOccurrences(of: ".local", with: "")
        }
        return ProcessInfo.processInfo.hostName
    }

    static func model() -> String {
        sysctlString("hw.model") ?? "Mac"
    }

    static func kernel() -> String {
        var info = utsname()
        guard uname(&info) == 0 else { return "Darwin" }
        let release = withUnsafeBytes(of: &info.release) { raw -> String in
            String(cString: raw.baseAddress!.assumingMemoryBound(to: CChar.self))
        }
        return "Darwin \(release)"
    }

    static func bootTime() -> Date {
        var boot = timeval()
        var size = MemoryLayout<timeval>.stride
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        guard sysctl(&mib, 2, &boot, &size, nil, 0) == 0 else { return Date() }
        return Date(timeIntervalSince1970: Double(boot.tv_sec) + Double(boot.tv_usec) / 1_000_000)
    }

    static func loadAverage() -> [Double] {
        var values = [Double](repeating: 0, count: 3)
        guard getloadavg(&values, 3) == 3 else { return [0, 0, 0] }
        return values
    }

    static func thermalState() -> String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return "NOMINAL"
        case .fair: return "ELEVATED"
        case .serious: return "SERIOUS"
        case .critical: return "CRITICAL"
        @unknown default: return "UNKNOWN"
        }
    }

    static func osVersion() -> String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }
}

// MARK: - sysctl helpers

func sysctlValue(_ name: String) -> UInt64? {
    var value: UInt64 = 0
    var size = MemoryLayout<UInt64>.stride
    guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
    return value
}

func sysctlString(_ name: String) -> String? {
    var size = 0
    guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
    var buffer = [CChar](repeating: 0, count: size)
    guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
    return String(cString: buffer)
}
