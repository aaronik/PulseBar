import Foundation

enum GraphTimeline {
    // The chart plots at most 48 samples; its left edge is the oldest plotted sample.
    static func label(for samples: [MetricSnapshot]) -> String {
        guard let first = samples.suffix(48).first, let last = samples.last else { return "0s ago" }
        let seconds = max(0, Int(last.timestamp.timeIntervalSince(first.timestamp).rounded()))
        if seconds < 60 { return "\(seconds)s ago" }
        let minutes = seconds / 60
        let remainder = seconds % 60
        return remainder == 0 ? "\(minutes)m ago" : "\(minutes)m \(remainder)s ago"
    }
}
