import AppKit
import Combine
import SwiftUI

@main
@MainActor
final class PulseBarApp: NSObject, NSApplicationDelegate {
    private let store = MonitorStore()
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var subscription: AnyCancellable?

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
        popover.animates = true
        popover.contentSize = NSSize(width: 360, height: 590)
        popover.contentViewController = NSHostingController(rootView: MonitorView(store: store))

        subscription = store.$history.sink { [weak self] history in
            guard let self else { return }
            self.renderStatus(history)
        }
        store.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.stop()
        subscription?.cancel()
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func renderStatus(_ history: [MetricSnapshot]) {
        guard let button = statusItem?.button else { return }
        let cpu = history.last?.cpu ?? 0
        let memory = history.last?.memory ?? 0
        button.imagePosition = .imageOnly
        button.image = StatusGraph.image(cpu: history.map(\.cpu), memory: history.map(\.memory), label: Int((cpu * 100).rounded()))
        button.toolTip = "CPU \(Int((cpu * 100).rounded()))% · Memory \(Int((memory * 100).rounded()))% (graph: 0–100%)"
        button.setAccessibilityValue("CPU \(Int((cpu * 100).rounded())) percent, memory \(Int((memory * 100).rounded())) percent")
    }
}

private enum StatusGraph {
    static func image(cpu: [Double], memory: [Double], label: Int) -> NSImage {
        let size = NSSize(width: 91, height: 20)
        let recentCPU = Array(cpu.suffix(30))
        let recentMemory = Array(memory.suffix(30))
        return NSImage(size: size, flipped: false) { rect in
            let fg = NSColor.labelColor
            let accent = NSColor.systemTeal
            let secondary = NSColor.systemPurple.withAlphaComponent(0.85)
            let graph = CGRect(x: 1, y: 3, width: 53, height: 14)
            drawBackdrop(in: graph)
            drawLine(recentMemory, in: graph, color: secondary, width: 1.25)
            drawLine(recentCPU, in: graph, color: accent, width: 1.6)
            let text = "\(label)%" as NSString
            text.draw(in: CGRect(x: 58, y: 1, width: 34, height: 17), withAttributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: fg
            ])
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
