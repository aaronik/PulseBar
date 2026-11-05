import Foundation

struct BatteryPoint: Codable, Sendable {
    let timestamp: Date
    let level: Double
    let isCharging: Bool
    let isPluggedIn: Bool
}

@MainActor
final class BatteryHistory {
    static let window: TimeInterval = 48 * 60 * 60
    static let sampleInterval: TimeInterval = 5 * 60
    static let maximumPoints = 600

    private(set) var points: [BatteryPoint] = []
    private let url: URL

    init(url: URL? = nil, now: Date = Date()) {
        self.url = url ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PulseBar", isDirectory: true)
            .appendingPathComponent("battery-history.json")
        if let data = try? Data(contentsOf: self.url),
           let decoded = try? JSONDecoder().decode([BatteryPoint].self, from: data) {
            points = Self.prune(decoded, now: now)
        }
    }

    @discardableResult
    func record(_ reading: BatteryReading, at now: Date = Date()) -> Bool {
        // Record on a five-minute cadence, or immediately when charging/power state changes.
        let changed = points.last.map {
            $0.isCharging != reading.isCharging || $0.isPluggedIn != reading.isPluggedIn
        } ?? true
        let due = now.timeIntervalSince(points.last?.timestamp ?? .distantPast) >= Self.sampleInterval
        let retained = Self.prune(points, now: now)
        guard changed || due || retained.count != points.count else { return false }
        points = retained
        if changed || due {
            points.append(BatteryPoint(timestamp: now, level: reading.level,
                                       isCharging: reading.isCharging, isPluggedIn: reading.isPluggedIn))
            points = Self.prune(points, now: now)
        }
        persist()
        return true
    }

    private static func prune(_ points: [BatteryPoint], now: Date) -> [BatteryPoint] {
        Array(points.filter {
            $0.timestamp >= now.addingTimeInterval(-window) && $0.timestamp <= now &&
            $0.level.isFinite && (0...1).contains($0.level)
        }.sorted { $0.timestamp < $1.timestamp }.suffix(maximumPoints))
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(points).write(to: url, options: .atomic)
        } catch {
            // The live battery display remains available if persistence is unavailable.
        }
    }
}
