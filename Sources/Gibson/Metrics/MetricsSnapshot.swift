import Foundation

/// Immutable view of the machine at one instant. Panels only ever read this,
/// which keeps sampling off the render path.
struct MetricsSnapshot {
    struct Memory {
        var total: UInt64 = 0
        var used: UInt64 = 0
        var wired: UInt64 = 0
        var compressed: UInt64 = 0
        var cached: UInt64 = 0
        var swapUsed: UInt64 = 0
        var swapTotal: UInt64 = 0

        var usedFraction: Double {
            total > 0 ? Double(used) / Double(total) : 0
        }
    }

    struct Volume {
        var name: String
        var total: UInt64
        var free: UInt64

        var used: UInt64 { total > free ? total - free : 0 }
        var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }
    }

    struct Network {
        var interface: String = "en0"
        var address: String = "0.0.0.0"
        var downBytesPerSecond: Double = 0
        var upBytesPerSecond: Double = 0
        var totalIn: UInt64 = 0
        var totalOut: UInt64 = 0
    }

    struct Process {
        var pid: Int32
        var user: String
        var command: String
        var cpu: Double
        var memory: UInt64
        var threads: Int
        var started: Date
    }

    var timestamp = Date()
    var isLive = true

    var hostName = "localhost"
    var userName = "user"
    var model = "Mac"
    var osVersion = "macOS"
    var kernel = "Darwin"
    var bootTime = Date()
    var uptime: TimeInterval = 0
    var thermalState = "NOMINAL"

    var cpuTotal: Double = 0
    var cpuUser: Double = 0
    var cpuSystem: Double = 0
    var cores: [Double] = []
    var cpuHistory: [Double] = []
    var loadAverage: [Double] = [0, 0, 0]

    var memory = Memory()
    var memoryHistory: [Double] = []

    var volumes: [Volume] = []
    var network = Network()
    var networkHistory: [Double] = []
    var processes: [Process] = []
    var processCount = 0
    var threadCount = 0

    /// Values used when live sampling is disabled or unavailable. Driven by the
    /// clock so the dashboard still breathes.
    static func simulated(at time: TimeInterval) -> MetricsSnapshot {
        var snapshot = MetricsSnapshot()
        snapshot.isLive = false
        snapshot.hostName = "node-07"
        snapshot.userName = "operator"
        snapshot.model = "Mac"
        snapshot.osVersion = "macOS"
        snapshot.kernel = "Darwin"
        snapshot.uptime = 3600 * 71 + time
        snapshot.cpuTotal = 34 + 26 * Double(noise(CGFloat(time) * 0.4))
        snapshot.cpuUser = snapshot.cpuTotal * 0.6
        snapshot.cpuSystem = snapshot.cpuTotal * 0.4
        snapshot.cores = (0 ..< 10).map { index in
            (20 + 70 * Double(noise(CGFloat(time) * 0.6 + CGFloat(index) * 7, seed: UInt64(index)))).clamped(0, 100)
        }
        snapshot.cpuHistory = (0 ..< 120).map { index in
            (25 + 55 * Double(noise(CGFloat(time) * 0.4 - CGFloat(index) * 0.12))).clamped(0, 100)
        }
        snapshot.loadAverage = [2.4, 2.1, 1.8]
        snapshot.memory = Memory(total: 32 << 30, used: 19 << 30, wired: 6 << 30,
                                 compressed: 2 << 30, cached: 5 << 30,
                                 swapUsed: 1 << 30, swapTotal: 4 << 30)
        snapshot.memoryHistory = (0 ..< 120).map { _ in 58 }
        snapshot.volumes = [Volume(name: "Macintosh HD", total: 994 << 30, free: 312 << 30)]
        snapshot.network = Network(interface: "en0", address: "10.0.0.42",
                                   downBytesPerSecond: 1_200_000 * Double(noise(CGFloat(time) * 0.9)),
                                   upBytesPerSecond: 320_000 * Double(noise(CGFloat(time) * 1.3 + 40)),
                                   totalIn: 84 << 30, totalOut: 12 << 30)
        snapshot.networkHistory = (0 ..< 120).map { index in
            Double(noise(CGFloat(time) - CGFloat(index) * 0.1)) * 100
        }
        snapshot.processCount = 421
        snapshot.threadCount = 2317
        snapshot.processes = SyntheticData.processes(count: 24, time: time)
        return snapshot
    }
}

extension MetricsSnapshot {
    var primaryVolume: Volume {
        volumes.first ?? Volume(name: "Macintosh HD", total: 0, free: 0)
    }
}
