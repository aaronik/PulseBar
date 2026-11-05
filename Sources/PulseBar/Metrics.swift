import Foundation
import AppKit
import Darwin

struct MetricSnapshot: Sendable {
    var timestamp: Date
    var cpu: Double
    var memory: Double
    var usedMemory: UInt64
    var totalMemory: UInt64
    var download: Double
    var upload: Double
    var diskUsed: UInt64
    var diskTotal: UInt64
    var battery: BatteryReading?
    var power: PowerReading?

    static let zero = MetricSnapshot(
        timestamp: .distantPast,
        cpu: 0,
        memory: 0,
        usedMemory: 0,
        totalMemory: 0,
        download: 0,
        upload: 0,
        diskUsed: 0,
        diskTotal: 0,
        battery: nil,
        power: nil
    )
}

@MainActor
final class MonitorStore: ObservableObject {
    @Published var snapshot: MetricSnapshot = .zero
    @Published var history: [MetricSnapshot] = []
    @Published private(set) var batteryHistory: [BatteryPoint] = []
    @Published var topCPUProcesses: [ProcessUsage] = []
    @Published var topMemoryProcesses: [ProcessUsage] = []

    private let batteryRecorder: BatteryHistory
    private var lastSystemBatteryRefresh: Date = .distantPast
    private var usingSystemBatteryHistory = false
    private let processSampler = ProcessSampler()
    private var processTask: Task<Void, Never>?
    private var processGeneration = 0
    private var timer: Timer?
    private(set) var refreshInterval: Double = 1
    private var previousCPU: [UInt64]?
    private var previousNetwork: [String: InterfaceCounters]?
    private var previousNetworkTime: Date?

    init(batteryHistoryURL: URL? = nil) {
        batteryRecorder = BatteryHistory(url: batteryHistoryURL)
        if batteryHistoryURL == nil, let system = SystemBatteryHistory.read(), !system.isEmpty {
            batteryHistory = system
            usingSystemBatteryHistory = true
            lastSystemBatteryRefresh = Date()
        } else {
            batteryHistory = batteryRecorder.points
        }
    }

    func start() {
        guard timer == nil else { return }
        poll()
        scheduleTimer()
    }

    func setRefreshInterval(_ interval: Double) {
        let adjusted = DisplaySettings.clampedInterval(interval)
        guard adjusted != refreshInterval else { return }
        refreshInterval = adjusted
        if timer != nil { scheduleTimer() }
        // Restart process sampling so the new cadence takes effect immediately.
        if processTask != nil {
            stopProcessSampling()
            startProcessSampling()
        }
    }

    private func scheduleTimer() {
        timer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.poll()
            }
        }
        timer.tolerance = min(0.5, refreshInterval * 0.1)
        self.timer = timer
    }

    func stop() {
        stopProcessSampling()
        timer?.invalidate()
        timer = nil
        previousCPU = nil
        previousNetwork = nil
        previousNetworkTime = nil
    }

    func startProcessSampling() {
        guard processTask == nil else { return }
        processGeneration += 1
        let generation = processGeneration
        processTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let result = await processSampler.sample()
                guard !Task.isCancelled, generation == processGeneration else { break }
                topCPUProcesses = result.cpu
                topMemoryProcesses = result.memory
                try? await Task.sleep(for: .seconds(refreshInterval))
            }
        }
    }

    func stopProcessSampling() {
        processGeneration += 1
        processTask?.cancel()
        processTask = nil
    }

    private func poll() {
        let now = Date()
        let cpu = cpuUsage() ?? snapshot.cpu
        let (usedMemory, totalMemory) = memoryUsage() ?? (snapshot.usedMemory, snapshot.totalMemory)
        let (download, upload) = networkRates(at: now)
        let (diskUsed, diskTotal) = diskUsage() ?? (snapshot.diskUsed, snapshot.diskTotal)
        let battery = BatterySampler.read()
        let power = battery == nil ? nil : PowerSampler.read()
        if let battery {
            _ = batteryRecorder.record(battery, at: now)
            if now.timeIntervalSince(lastSystemBatteryRefresh) >= BatteryHistory.sampleInterval {
                lastSystemBatteryRefresh = now
                if let system = SystemBatteryHistory.read(now: now), !system.isEmpty {
                    batteryHistory = system
                    usingSystemBatteryHistory = true
                } else {
                    usingSystemBatteryHistory = false
                }
            }
            if !usingSystemBatteryHistory {
                batteryHistory = batteryRecorder.points
            }
        }

        let current = MetricSnapshot(
            timestamp: now,
            cpu: cpu,
            memory: totalMemory == 0 ? 0 : Double(usedMemory) / Double(totalMemory),
            usedMemory: usedMemory,
            totalMemory: totalMemory,
            download: download,
            upload: upload,
            diskUsed: diskUsed,
            diskTotal: diskTotal,
            battery: battery,
            power: power
        )
        snapshot = current
        history.append(current)
        if history.count > 60 {
            history.removeFirst(history.count - 60)
        }
    }

    private func cpuUsage() -> Double? {
        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS, count >= mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size) else { return nil }
        let ticks = withUnsafeBytes(of: info.cpu_ticks) {
            $0.bindMemory(to: UInt32.self).map(UInt64.init)
        }
        guard ticks.count >= Int(CPU_STATE_MAX) else { return nil }
        defer { previousCPU = ticks }
        guard let previous = previousCPU, previous.count == ticks.count,
              zip(ticks, previous).allSatisfy({ $0 >= $1 }) else { return 0 }

        let deltas = zip(ticks, previous).map(-)
        let total = deltas.reduce(UInt64(0), +)
        guard total > 0 else { return 0 }
        let idle = deltas[Int(CPU_STATE_IDLE)]
        return min(1, max(0, Double(total - idle) / Double(total)))
    }

    private func memoryUsage() -> (UInt64, UInt64)? {
        let total = ProcessInfo.processInfo.physicalMemory
        guard total > 0 else { return nil }
        var info = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        // The kernel may return fewer trailing fields than this SDK's structure.
        // The page counts used below occupy the first eight integer slots.
        guard result == KERN_SUCCESS, count >= 8 else { return nil }

        // Inactive pages are reclaimable; speculative pages are included in inactive.
        let availablePages = UInt64(info.free_count) + UInt64(info.inactive_count)
        let pageSize = sysconf(_SC_PAGESIZE)
        guard pageSize > 0 else { return nil }
        let pageBytes = UInt64(pageSize)
        let available = availablePages.multipliedReportingOverflow(by: pageBytes)
        let freeBytes = available.overflow ? total : min(total, available.partialValue)
        return (total - freeBytes, total)
    }

    private struct InterfaceCounters {
        let received: UInt64
        let sent: UInt64
    }

    private func networkRates(at now: Date) -> (Double, Double) {
        guard let current = networkCounters() else { return (0, 0) }
        defer {
            previousNetwork = current
            previousNetworkTime = now
        }
        guard let previous = previousNetwork, let time = previousNetworkTime else { return (0, 0) }
        let interval = now.timeIntervalSince(time)
        guard interval > 0 else { return (0, 0) }

        var received: UInt64 = 0
        var sent: UInt64 = 0
        for (name, counters) in current {
            guard let old = previous[name] else { continue }
            // An interface can reset independently (e.g. when a VPN reconnects).
            if counters.received >= old.received {
                let delta = counters.received - old.received
                received = received.addingReportingOverflow(delta).overflow ? UInt64.max : received + delta
            }
            if counters.sent >= old.sent {
                let delta = counters.sent - old.sent
                sent = sent.addingReportingOverflow(delta).overflow ? UInt64.max : sent + delta
            }
        }
        return (Double(received) / interval, Double(sent) / interval)
    }

    private func networkCounters() -> [String: InterfaceCounters]? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return nil }
        defer { freeifaddrs(first) }

        var counters: [String: InterfaceCounters] = [:]
        var node: UnsafeMutablePointer<ifaddrs>? = first
        while let address = node {
            let interface = address.pointee
            defer { node = interface.ifa_next }
            guard let socket = interface.ifa_addr, socket.pointee.sa_family == UInt8(AF_LINK),
                  interface.ifa_flags & UInt32(IFF_UP) != 0,
                  interface.ifa_flags & UInt32(IFF_LOOPBACK) == 0,
                  let data = interface.ifa_data else { continue }
            let name = String(cString: interface.ifa_name)
            guard counters[name] == nil else { continue }
            let stats = data.assumingMemoryBound(to: if_data.self).pointee
            counters[name] = InterfaceCounters(received: UInt64(stats.ifi_ibytes), sent: UInt64(stats.ifi_obytes))
        }
        return counters
    }

    private func diskUsage() -> (UInt64, UInt64)? {
        guard let values = try? URL(fileURLWithPath: "/", isDirectory: true)
            .resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey]),
              let capacity = values.volumeTotalCapacity, capacity > 0,
              let available = values.volumeAvailableCapacity, available >= 0 else { return nil }
        let total = UInt64(capacity)
        return (total - min(total, UInt64(available)), total)
    }
}
