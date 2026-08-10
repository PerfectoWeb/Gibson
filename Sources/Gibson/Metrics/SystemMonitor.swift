import Foundation

/// Samples the host on a background queue and publishes immutable snapshots.
/// Shared across displays: a multi monitor setup creates one saver view per
/// screen and they all read the same data.
final class SystemMonitor {
    static let shared = SystemMonitor()

    private let queue = DispatchQueue(label: "com.gibson.metrics", qos: .utility)
    private let lock = NSLock()
    private let cpuSampler = CPUSampler()
    private let networkSampler = NetworkSampler()
    private let processSampler = ProcessSampler()

    private var timer: DispatchSourceTimer?
    private var clients = 0
    private var tick = 0
    private var current = MetricsSnapshot()

    private static let historyLength = 120
    private static let processLimit = 32

    private init() {}

    var snapshot: MetricsSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    func retain() {
        lock.lock()
        clients += 1
        let shouldStart = clients == 1
        lock.unlock()
        guard shouldStart else { return }

        queue.async { [weak self] in
            self?.loadStaticInfo()
            self?.refresh()
        }

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in self?.refresh() }
        timer.resume()
        self.timer = timer
    }

    func release() {
        lock.lock()
        clients = max(0, clients - 1)
        let shouldStop = clients == 0
        lock.unlock()
        guard shouldStop else { return }
        timer?.cancel()
        timer = nil
    }

    // MARK: - Sampling

    private func loadStaticInfo() {
        var snapshot = current
        snapshot.hostName = HostSampler.hostName()
        snapshot.userName = NSUserName()
        snapshot.model = HostSampler.model()
        snapshot.osVersion = HostSampler.osVersion()
        snapshot.kernel = HostSampler.kernel()
        snapshot.bootTime = HostSampler.bootTime()
        snapshot.volumes = StorageSampler.sample()
        publish(snapshot)
    }

    private func refresh() {
        var snapshot = current
        snapshot.timestamp = Date()
        snapshot.isLive = true
        snapshot.uptime = Date().timeIntervalSince(snapshot.bootTime)
        snapshot.thermalState = HostSampler.thermalState()
        snapshot.loadAverage = HostSampler.loadAverage()

        let cpu = cpuSampler.sample()
        if !cpu.cores.isEmpty {
            snapshot.cpuTotal = cpu.total
            snapshot.cpuUser = cpu.user
            snapshot.cpuSystem = cpu.system
            snapshot.cores = cpu.cores
        }
        append(&snapshot.cpuHistory, snapshot.cpuTotal)

        snapshot.memory = MemorySampler.sample()
        append(&snapshot.memoryHistory, snapshot.memory.usedFraction * 100)

        snapshot.network = networkSampler.sample()
        let throughput = (snapshot.network.downBytesPerSecond + snapshot.network.upBytesPerSecond)
        append(&snapshot.networkHistory, throughput)

        if tick % 3 == 0 {
            let processes = processSampler.sample(limit: Self.processLimit)
            if !processes.rows.isEmpty {
                snapshot.processes = processes.rows
                snapshot.processCount = processes.processCount
                snapshot.threadCount = processes.threadCount
            }
        }

        if tick % 15 == 0 {
            let volumes = StorageSampler.sample()
            if !volumes.isEmpty { snapshot.volumes = volumes }
        }

        tick &+= 1
        publish(snapshot)
    }

    private func append(_ history: inout [Double], _ value: Double) {
        history.append(value)
        if history.count > Self.historyLength {
            history.removeFirst(history.count - Self.historyLength)
        }
    }

    private func publish(_ snapshot: MetricsSnapshot) {
        lock.lock()
        current = snapshot
        lock.unlock()
    }
}
