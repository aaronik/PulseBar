import AppKit
import SwiftUI

struct MonitorView: View {
    @ObservedObject var store: MonitorStore
    @ObservedObject var settings: DisplaySettings

    private var snapshot: MetricSnapshot { store.snapshot }

    private var graphHistory: [MetricSnapshot] {
        let recent = Array(store.history.suffix(47))
        return recent.last?.timestamp == snapshot.timestamp ? recent : recent + [snapshot]
    }

    // Use the exact same ceiling for the network graph and its vertical axis.
    private var networkCeiling: Double {
        let peak = graphHistory.reduce(0.0) { max($0, $1.download, $1.upload) }
        return max(peak * 1.15, 1)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            separator
            cpuSection
            separator
            memorySection
            separator
            networkSection
            separator
            diskSection
            separator
            displaySection
            separator
            footer
        }
        .frame(width: 360)
        .background(Palette.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: 24, y: 12)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Palette.cyan)
                .frame(width: 34, height: 34)
                .background(Palette.cyan.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))

            Text("PULSE")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .tracking(2.5)
                .foregroundStyle(Palette.primary)

            Spacer()

            HStack(spacing: 6) {
                Circle()
                    .fill(Palette.green)
                    .frame(width: 6, height: 6)
                    .shadow(color: Palette.green.opacity(0.7), radius: 5)
                Text("LIVE")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.2)
            }
            .foregroundStyle(Palette.green)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Palette.green.opacity(0.10), in: Capsule())
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var cpuSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    sectionLabel("PROCESSOR", symbol: "cpu", color: Palette.cyan)
                    Text("CPU Usage")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Palette.secondary)
                }
                Spacer()
                Text(percent(snapshot.cpu))
                    .font(.system(size: 34, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Palette.primary)
            }

            MonitorGraph(
                series: [graphHistory.map(\.cpu)],
                colors: [Palette.cyan],
                ceiling: 1,
                fillFirst: true
            )
            .frame(height: 76)
            .overlay(alignment: .trailing) {
                verticalPercentAxis
            }
            .accessibilityLabel("CPU history, zero to one hundred percent")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 17)
    }

    private var memorySection: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                sectionLabel("MEMORY", symbol: "memorychip", color: Palette.purple)
                Spacer()
                Text(percent(snapshot.memory))
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Palette.primary)
            }
            MonitorGraph(
                series: [graphHistory.map(\.memory)],
                colors: [Palette.purple],
                ceiling: 1,
                fillFirst: true
            )
            .frame(height: 62)
            .overlay(alignment: .trailing) {
                verticalPercentAxis
            }
            .accessibilityLabel("Memory history, zero to one hundred percent")

            HStack {
                Text("\(byteString(snapshot.usedMemory)) used")
                    .foregroundStyle(Palette.secondary)
                Spacer()
                Text("\(byteString(snapshot.totalMemory)) total")
                    .foregroundStyle(Palette.muted)
            }
            .font(.system(size: 11, weight: .medium, design: .monospaced))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
    }

    private var networkSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("NETWORK", symbol: "network", color: Palette.lime)

            HStack(alignment: .top, spacing: 0) {
                trafficValue("DOWNLOAD", symbol: "arrow.down.right", value: snapshot.download, color: Palette.lime)
                Spacer(minLength: 8)
                trafficValue("UPLOAD", symbol: "arrow.up.right", value: snapshot.upload, color: Palette.orange)
            }

            MonitorGraph(
                series: [graphHistory.map(\.download), graphHistory.map(\.upload)],
                colors: [Palette.lime, Palette.orange],
                ceiling: networkCeiling,
                fillFirst: false
            )
            .frame(height: 62)
            .overlay(alignment: .trailing) {
                graphAxis(top: "\(byteString(networkCeiling))/s", bottom: "0 B/s")
            }
            .accessibilityLabel("Network history, zero to \(byteString(networkCeiling)) per second")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
    }

    private var diskSection: some View {
        let fraction = snapshot.diskTotal == 0
            ? 0 : Double(snapshot.diskUsed) / Double(snapshot.diskTotal)

        return VStack(alignment: .leading, spacing: 13) {
            HStack {
                sectionLabel("STORAGE", symbol: "internaldrive", color: Palette.orange)
                Spacer()
                Text(percent(fraction))
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Palette.primary)
            }
            usageBar(fraction: fraction, color: Palette.orange)
            HStack {
                Text("\(byteString(snapshot.diskUsed)) used")
                    .foregroundStyle(Palette.secondary)
                Spacer()
                Text("\(byteString(snapshot.diskTotal)) total")
                    .foregroundStyle(Palette.muted)
            }
            .font(.system(size: 11, weight: .medium, design: .monospaced))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
    }

    private var displaySection: some View {
        VStack(alignment: .leading, spacing: 13) {
            sectionLabel("MENU BAR", symbol: "slider.horizontal.3", color: Palette.cyan)
            HStack(spacing: 8) {
                displayToggle("CPU %", isOn: $settings.cpuPercent, color: Palette.primary)
                displayToggle("Memory", isOn: $settings.memoryGraph, color: Palette.purple)
                displayToggle("CPU", isOn: $settings.cpuGraph, color: Palette.cyan)
            }
            HStack(spacing: 8) {
                displayToggle("Network ↑", isOn: $settings.networkUp, color: Palette.orange)
                displayToggle("Network ↓", isOn: $settings.networkDown, color: Palette.lime)
                Spacer(minLength: 0)
            }
            Text("Network lines share a scale set by the highest observed rate.")
                .font(.system(size: 10))
                .foregroundStyle(Palette.muted)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private func displayToggle(_ title: String, isOn: Binding<Bool>, color: Color) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 5) {
                Circle().fill(color).frame(width: 6, height: 6)
                Text(title).lineLimit(1)
            }
            .font(.system(size: 11, weight: .medium))
        }
        .toggleStyle(.button)
        .buttonStyle(.plain)
        .foregroundStyle(isOn.wrappedValue ? Palette.primary : Palette.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(isOn.wrappedValue ? color.opacity(0.16) : Palette.track, in: Capsule())
        .overlay(Capsule().strokeBorder(isOn.wrappedValue ? color.opacity(0.45) : Palette.border))
        .accessibilityLabel(title)
        .accessibilityValue(isOn.wrappedValue ? "On" : "Off")
        .help("Show \(title) in the menu bar")
    }

    private var footer: some View {
        HStack {
            Text("PULSEBAR")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .tracking(1.5)
                .foregroundStyle(Palette.muted)
            Spacer()
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "power")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Quit")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(Palette.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Quit PulseBar")
        }
        .padding(.leading, 20)
        .padding(.trailing, 12)
        .padding(.vertical, 10)
    }

    private var verticalPercentAxis: some View {
        graphAxis(top: "100%", bottom: "0%")
    }

    private func graphAxis(top: String, bottom: String) -> some View {
        VStack(alignment: .trailing) {
            Text(top)
            Spacer()
            Text(bottom)
        }
        .font(.system(size: 9, weight: .medium, design: .monospaced))
        .foregroundStyle(Palette.muted)
        .padding(.leading, 5)
        .background(Palette.background.opacity(0.85))
    }

    private var separator: some View {
        Rectangle()
            .fill(Palette.border)
            .frame(height: 1)
    }

    private func sectionLabel(_ title: String, symbol: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 16)
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(1.5)
                .foregroundStyle(Palette.secondary)
        }
    }

    private func trafficValue(_ title: String, symbol: String, value: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .foregroundStyle(color)
                Text(title)
                    .foregroundStyle(Palette.muted)
            }
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .tracking(0.9)
            Text("\(byteString(value))/s")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Palette.primary)
        }
    }

    private func usageBar(fraction: Double, color: Color) -> some View {
        GeometryReader { geometry in
            Capsule()
                .fill(Palette.track)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(color.gradient)
                        .frame(width: geometry.size.width * clamped(fraction))
                }
        }
        .frame(height: 7)
        .accessibilityLabel("\(percent(fraction)) used")
    }

    private func percent(_ value: Double) -> String {
        String(format: "%.0f%%", clamped(value) * 100)
    }

    private func clamped(_ value: Double) -> Double {
        value.isFinite ? min(max(value, 0), 1) : 0
    }

    private func byteString(_ value: UInt64) -> String {
        byteString(Double(value))
    }

    private func byteString(_ value: Double) -> String {
        let units = ["B", "KB", "MB", "GB", "TB", "PB"]
        var size = value.isFinite ? max(value, 0) : 0
        var unit = 0
        while size >= 1024 && unit < units.count - 1 {
            size /= 1024
            unit += 1
        }
        return unit == 0
            ? String(format: "%.0f %@", size, units[unit])
            : String(format: "%.1f %@", size, units[unit])
    }
}

private enum Palette {
    static let background = Color(red: 0.075, green: 0.090, blue: 0.115)
    static let border = Color.white.opacity(0.085)
    static let track = Color.white.opacity(0.09)
    static let primary = Color(red: 0.94, green: 0.96, blue: 0.98)
    static let secondary = Color(red: 0.64, green: 0.69, blue: 0.75)
    static let muted = Color(red: 0.42, green: 0.47, blue: 0.54)
    static let cyan = Color(red: 0.30, green: 0.81, blue: 0.94)
    static let green = Color(red: 0.36, green: 0.87, blue: 0.65)
    static let lime = Color(red: 0.81, green: 0.91, blue: 0.23)
    static let purple = Color(red: 0.69, green: 0.57, blue: 0.98)
    static let orange = Color(red: 1.0, green: 0.68, blue: 0.39)
}

private struct MonitorGraph: View {
    let series: [[Double]]
    let colors: [Color]
    var ceiling: Double? = nil
    var fillFirst = false

    var body: some View {
        Canvas { context, size in
            guard size.width > 0, size.height > 0 else { return }
            let inset: CGFloat = 2
            let height = size.height - inset * 2

            for step in 0...2 {
                let y = inset + height * CGFloat(step) / 2
                var grid = Path()
                grid.move(to: CGPoint(x: 0, y: y))
                grid.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(grid, with: .color(.white.opacity(0.07)), lineWidth: 1)
            }

            let highest = series.flatMap { $0 }.filter { $0.isFinite }.max() ?? 0
            let scale = max(ceiling ?? (highest * 1.15), 1e-9)

            for (index, samples) in series.enumerated() where index < colors.count {
                let values = Array(samples.suffix(48))
                guard !values.isEmpty else { continue }
                let points = values.enumerated().map { offset, value in
                    CGPoint(
                        x: size.width * CGFloat(offset) / CGFloat(max(values.count - 1, 1)),
                        y: inset + height * (1 - CGFloat(min(max(value.isFinite ? value : 0, 0) / scale, 1)))
                    )
                }
                var line = Path()
                line.move(to: points[0])
                for point in points.dropFirst() { line.addLine(to: point) }
                if points.count == 1 {
                    line.addLine(to: CGPoint(x: size.width, y: points[0].y))
                }

                if fillFirst && index == 0 {
                    var area = line
                    area.addLine(to: CGPoint(x: size.width, y: size.height))
                    area.addLine(to: CGPoint(x: points[0].x, y: size.height))
                    area.closeSubpath()
                    context.fill(area, with: .linearGradient(
                        Gradient(colors: [colors[index].opacity(0.28), colors[index].opacity(0.01)]),
                        startPoint: .zero,
                        endPoint: CGPoint(x: 0, y: size.height)
                    ))
                }
                context.stroke(line, with: .color(colors[index]), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                if let last = points.last {
                    context.fill(Path(ellipseIn: CGRect(x: last.x - 3, y: last.y - 3, width: 6, height: 6)), with: .color(colors[index]))
                }
            }
        }
        .accessibilityHidden(true)
    }
}
