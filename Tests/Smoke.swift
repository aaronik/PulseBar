import Foundation
import AppKit

@main
@MainActor
struct Smoke {
    static func main() async throws {
        let store = MonitorStore()
        store.start()
        store.start()
        try await Task.sleep(for: .seconds(2.3))
        let sample = store.snapshot
        precondition((2...4).contains(store.history.count), "Timer was duplicated or did not run")
        precondition(sample.cpu.isFinite && (0...1).contains(sample.cpu), "Invalid CPU")
        precondition((0...1).contains(sample.memory), "Invalid memory")
        precondition(sample.totalMemory > 0 && sample.usedMemory <= sample.totalMemory, "Invalid RAM capacity")
        precondition(sample.diskTotal > 0 && sample.diskUsed <= sample.diskTotal, "Invalid disk capacity")
        precondition(sample.download.isFinite && sample.download >= 0, "Invalid download")
        precondition(sample.upload.isFinite && sample.upload >= 0, "Invalid upload")
        if let battery = BatterySampler.read() {
            precondition((0...1).contains(battery.level), "Invalid battery percentage")
            precondition(!store.batteryHistory.isEmpty, "No battery history recorded")
            precondition(sample.battery != nil, "Battery missing from metric history")
            precondition(abs((sample.battery?.level ?? 0) - battery.level) <= 0.05,
                         "Battery history differs from power source")
        } else {
            precondition(sample.battery == nil, "No-battery machine should omit battery reading")
        }
        store.setRefreshInterval(4)
        precondition(store.refreshInterval == 4, "Refresh rate did not change")
        let slowCount = store.history.count
        try await Task.sleep(for: .seconds(1.3))
        precondition(store.history.count == slowCount, "Metrics refreshed before configured interval")
        store.setRefreshInterval(1)
        try await Task.sleep(for: .seconds(1.3))
        precondition(store.history.count > slowCount, "Timer did not resume at faster interval")
        store.stop()
        let count = store.history.count
        try await Task.sleep(for: .seconds(1.2))
        precondition(store.history.count == count, "Timer continued after stop")

        let base = Date(timeIntervalSince1970: 1000)
        let timeline = (0..<60).map { index -> MetricSnapshot in
            var point = MetricSnapshot.zero
            point.timestamp = base.addingTimeInterval(Double(index * 5))
            return point
        }
        precondition(GraphTimeline.label(for: []) == "0s ago")
        precondition(GraphTimeline.label(for: [timeline[0]]) == "0s ago")
        precondition(GraphTimeline.label(for: Array(timeline.prefix(13))) == "1m ago")
        precondition(GraphTimeline.label(for: timeline) == "3m 55s ago",
                     "Time axis must use the 48 samples actually plotted")

        if let systemHistory = SystemBatteryHistory.read() {
            precondition(systemHistory.count <= 600, "System battery history exceeded chart capacity")
            precondition(systemHistory.allSatisfy { (0...1).contains($0.level) }, "Invalid system battery level")
            precondition(zip(systemHistory, systemHistory.dropFirst()).allSatisfy {
                $0.timestamp <= $1.timestamp
            }, "System battery history is out of order")
        }
        precondition(SystemBatteryHistory.read(path: "/not/a/powerlog.db") == nil,
                     "Inaccessible system history should fall back safely")

        let historyURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PulseBar-Smoke-\(UUID().uuidString)/battery-history.json")
        defer { try? FileManager.default.removeItem(at: historyURL.deletingLastPathComponent()) }
        let recorder = BatteryHistory(url: historyURL, now: base)
        let reading = BatteryReading(level: 0.65, isCharging: false, isPluggedIn: false)
        precondition(recorder.record(reading, at: base))
        precondition(!recorder.record(reading, at: base.addingTimeInterval(60)), "Battery sampled too often")
        precondition(recorder.record(reading, at: base.addingTimeInterval(300)))
        precondition(recorder.record(BatteryReading(level: 0.66, isCharging: true, isPluggedIn: true),
                                    at: base.addingTimeInterval(301)), "Charging transition not captured")
        let loaded = BatteryHistory(url: historyURL, now: base.addingTimeInterval(301))
        precondition(loaded.points.count == 3, "Battery history did not survive reload")
        let expired = BatteryHistory(url: historyURL, now: base.addingTimeInterval(BatteryHistory.window + 302))
        precondition(expired.points.isEmpty, "Old battery readings were not pruned")

        let sampler = ProcessSampler()
        _ = await sampler.sample()
        try await Task.sleep(for: .seconds(1.2))
        let processes = await sampler.sample()
        precondition(!processes.memory.isEmpty && processes.memory.count <= 5, "Missing memory rankings")
        precondition(!processes.cpu.isEmpty && processes.cpu.count <= 5, "Missing CPU rankings")
        precondition(zip(processes.cpu, processes.cpu.dropFirst()).allSatisfy { $0.cpu >= $1.cpu })
        precondition(zip(processes.memory, processes.memory.dropFirst()).allSatisfy { $0.residentBytes >= $1.residentBytes })

        let suite = "PulseBar.Smoke.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = DisplaySettings(defaults: defaults)
        precondition(settings.cpuPercent && settings.cpuGraph && settings.memoryGraph)
        precondition(!settings.networkUp && !settings.networkDown)
        precondition(settings.refreshInterval == 1)
        settings.refreshInterval = 5
        settings.cpuPercent = false
        settings.cpuGraph = false
        settings.memoryGraph = false
        settings.networkUp = true
        precondition(!settings.showsUsageGraph && settings.showsNetworkGraph)
        let restored = DisplaySettings(defaults: defaults)
        precondition(!restored.cpuPercent && !restored.cpuGraph && !restored.memoryGraph)
        precondition(restored.networkUp && !restored.networkDown, "Preferences did not persist independently")
        precondition(restored.refreshInterval == 5, "Refresh interval did not persist")
        restored.refreshInterval = 100
        precondition(restored.refreshInterval == 10, "Refresh interval was not clamped")
        restored.networkDown = true
        precondition(restored.networkUp && restored.networkDown)
        print("PASS: \(count) live samples, independent persistent toggles; CPU \(Int(sample.cpu * 100))%, RAM \(Int(sample.memory * 100))%")
    }
}
