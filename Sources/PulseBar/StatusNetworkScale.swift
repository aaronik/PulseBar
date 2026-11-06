import Foundation

enum StatusNetworkScale {
    static let sampleCount = 30
    static let minimumBytesPerSecond = 4_096.0

    /// Upload and download share a scale based only on the samples currently drawn.
    static func bytesPerSecond(for history: [MetricSnapshot]) -> Double {
        let peak = history.suffix(sampleCount).reduce(0.0) { maximum, sample in
            let rates = [sample.download, sample.upload].filter { $0.isFinite && $0 >= 0 }
            return max(maximum, rates.max() ?? 0)
        }
        return max(minimumBytesPerSecond, peak * 1.15)
    }
}
