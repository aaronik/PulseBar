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
        store.stop()
        let count = store.history.count
        try await Task.sleep(for: .seconds(1.2))
        precondition(store.history.count == count, "Timer continued after stop")
        print("PASS: \(count) live samples; CPU \(Int(sample.cpu * 100))%, RAM \(Int(sample.memory * 100))%, network \(Int(sample.download)) down / \(Int(sample.upload)) up B/s")
    }
}
