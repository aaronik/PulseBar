import Foundation
import Combine

@MainActor
final class DisplaySettings: ObservableObject {
    private enum Key {
        static let cpuPercent = "display.cpuPercent"
        static let memoryGraph = "display.memoryGraph"
        static let cpuGraph = "display.cpuGraph"
        static let networkUp = "display.networkUp"
        static let networkDown = "display.networkDown"
    }

    @Published var cpuPercent: Bool { didSet { defaults.set(cpuPercent, forKey: Key.cpuPercent) } }
    @Published var memoryGraph: Bool { didSet { defaults.set(memoryGraph, forKey: Key.memoryGraph) } }
    @Published var cpuGraph: Bool { didSet { defaults.set(cpuGraph, forKey: Key.cpuGraph) } }
    @Published var networkUp: Bool { didSet { defaults.set(networkUp, forKey: Key.networkUp) } }
    @Published var networkDown: Bool { didSet { defaults.set(networkDown, forKey: Key.networkDown) } }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Only the existing CPU and memory display is on by default.
        cpuPercent = defaults.object(forKey: Key.cpuPercent) as? Bool ?? true
        memoryGraph = defaults.object(forKey: Key.memoryGraph) as? Bool ?? true
        cpuGraph = defaults.object(forKey: Key.cpuGraph) as? Bool ?? true
        networkUp = defaults.object(forKey: Key.networkUp) as? Bool ?? false
        networkDown = defaults.object(forKey: Key.networkDown) as? Bool ?? false
    }

    var showsUsageGraph: Bool { cpuGraph || memoryGraph }
    var showsNetworkGraph: Bool { networkUp || networkDown }
}
