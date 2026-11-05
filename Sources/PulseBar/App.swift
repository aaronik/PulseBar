import AppKit
import Combine
import SwiftUI

@main
@MainActor
final class PulseBarApp: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let store = MonitorStore()
    private let settings = DisplaySettings()
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var subscriptions = Set<AnyCancellable>()
    private var peakNetworkRate: Double = 0

    static func main() {
        let app = NSApplication.shared
        let delegate = PulseBarApp()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: 96)
        statusItem = item
        guard let button = item.button else { return }
        button.target = self
        button.action = #selector(togglePopover)
        button.toolTip = "PulseBar — system activity"
        button.setAccessibilityLabel("PulseBar system activity")

        popover.behavior = .transient
        popover.delegate = self
        popover.animates = true
        popover.contentSize = NSSize(width: 360, height: 590)
        popover.contentViewController = NSHostingController(rootView: MonitorView(store: store, settings: settings))

        store.$history.dropFirst().sink { [weak self] history in
            guard let self else { return }
            if let last = history.last {
                self.peakNetworkRate = max(self.peakNetworkRate, last.upload, last.download)
            }
            self.renderStatus(history)
        }.store(in: &subscriptions)
        settings.objectWillChange.sink { [weak self] _ in
            // @Published emits before changing its property; render on the next main-loop turn.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.renderStatus(self.store.history)
            }
        }.store(in: &subscriptions)
        renderStatus([])
        store.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.stop()
        subscriptions.removeAll()
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            let available = button.window?.screen?.visibleFrame.height ?? 800
            popover.contentSize = NSSize(width: 360, height: min(920, max(400, available - 44)))
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    func popoverDidShow(_ notification: Notification) {
        store.startProcessSampling()
    }

    func popoverDidClose(_ notification: Notification) {
        store.stopProcessSampling()
    }

    private func renderStatus(_ history: [MetricSnapshot]) {
        guard let item = statusItem, let button = item.button else { return }
        let cpu = history.last?.cpu ?? 0
        let memory = history.last?.memory ?? 0
        let upload = history.last?.upload ?? 0
        let download = history.last?.download ?? 0
        let hasGraph = settings.showsUsageGraph || settings.showsNetworkGraph
        // Keep a clickable icon even when every metric is switched off.
        let width: CGFloat = (hasGraph ? 58 : 18) + (settings.cpuPercent ? 37 : 0)
        item.length = width
        button.imagePosition = .imageOnly
        button.image = StatusGraph.image(history: history, settings: settings, peakNetworkRate: peakNetworkRate)
        button.toolTip = "CPU \(Int((cpu * 100).rounded()))% · Memory \(Int((memory * 100).rounded()))% · ↓ \(Int(download)) B/s · ↑ \(Int(upload)) B/s"
        button.setAccessibilityValue("CPU \(Int((cpu * 100).rounded())) percent, memory \(Int((memory * 100).rounded())) percent, download \(Int(download)) bytes per second, upload \(Int(upload)) bytes per second")
    }
}

@MainActor
private enum StatusGraph {
    static func image(history: [MetricSnapshot], settings: DisplaySettings, peakNetworkRate: Double) -> NSImage {
        let samples = Array(history.suffix(30))
        let hasGraph = settings.showsUsageGraph || settings.showsNetworkGraph
        let size = NSSize(width: (hasGraph ? 54 : 14) + (settings.cpuPercent ? 37 : 0), height: 20)
        let label = Int(((samples.last?.cpu ?? 0) * 100).rounded())
        let cpuEnabled = settings.cpuGraph
        let memoryEnabled = settings.memoryGraph
        let upEnabled = settings.networkUp
        let downEnabled = settings.networkDown
        let percentEnabled = settings.cpuPercent
        let networkScale = max(peakNetworkRate, 1)
        return NSImage(size: size, flipped: false) { _ in
            if hasGraph {
                let graph = CGRect(x: 1, y: 3, width: 53, height: 14)
                drawBackdrop(in: graph)
                if memoryEnabled {
                    drawLine(samples.map(\.memory), in: graph, color: NSColor.systemPurple.withAlphaComponent(0.85), width: 1.25)
                }
                if downEnabled {
                    drawLine(samples.map { $0.download / networkScale }, in: graph, color: NSColor(calibratedRed: 0.81, green: 0.91, blue: 0.23, alpha: 1), width: 1.35)
                }
                if upEnabled {
                    drawLine(samples.map { $0.upload / networkScale }, in: graph, color: NSColor.systemOrange, width: 1.35)
                }
                if cpuEnabled {
                    drawLine(samples.map(\.cpu), in: graph, color: NSColor.systemTeal, width: 1.6)
                }
            } else if !percentEnabled {
                // Never strand the user with an invisible, unclickable status item.
                let icon = NSImage(systemSymbolName: "waveform.path.ecg", accessibilityDescription: "PulseBar")
                icon?.draw(in: CGRect(x: 0, y: 2, width: 14, height: 15))
            }
            if percentEnabled {
                let text = "\(label)%" as NSString
                text.draw(in: CGRect(x: hasGraph ? 58 : 2, y: 1, width: 34, height: 17), withAttributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
                    .foregroundColor: NSColor.labelColor
                ])
            }
            return true
        }
    }

    private static func drawBackdrop(in rect: CGRect) {
        // The line graph uses a fixed 0–100% scale: bottom = idle, top = full.
        let background = NSBezierPath(roundedRect: rect.insetBy(dx: -1, dy: -2), xRadius: 3, yRadius: 3)
        NSColor.labelColor.withAlphaComponent(0.055).setFill()
        background.fill()

        let guides = NSBezierPath()
        guides.lineWidth = 0.5
        for fraction in [CGFloat(0), 0.5, 1] {
            let y = rect.minY + rect.height * fraction
            guides.move(to: CGPoint(x: rect.minX, y: y))
            guides.line(to: CGPoint(x: rect.maxX, y: y))
        }
        NSColor.labelColor.withAlphaComponent(0.22).setStroke()
        guides.stroke()
    }

    private static func drawLine(_ values: [Double], in rect: CGRect, color: NSColor, width: CGFloat) {
        let path = NSBezierPath()
        path.lineWidth = width
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        for (index, value) in values.enumerated() {
            // Right-align the timeline so the graph grows leftward during startup.
            let x = rect.minX + rect.width * CGFloat(30 - values.count + index) / 29
            let y = rect.minY + rect.height * CGFloat(min(1, max(0, value)))
            if index == 0 { path.move(to: CGPoint(x: x, y: y)) }
            else { path.line(to: CGPoint(x: x, y: y)) }
        }
        color.setStroke()
        path.stroke()
    }
}
