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

    // Battery uses a fixed two-day window rather than the short metric history.
    private var batteryChartEnd: Date {
        snapshot.timestamp == .distantPast ? Date() : snapshot.timestamp
    }

    private var batteryChartStart: Date {
        batteryChartEnd.addingTimeInterval(-BatteryHistory.window)
    }

    private var batteryPoints: [BatteryPoint] {
        store.batteryHistory.filter { $0.timestamp >= batteryChartStart && $0.timestamp <= batteryChartEnd }
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
            ScrollView {
                VStack(spacing: 0) {
                    cpuSection
                    separator
                    memorySection
                    separator
                    networkSection
                    if snapshot.battery != nil {
                        separator
                        batterySection
                        if snapshot.power != nil {
                            separator
                            powerSection
                        }
                    }
                    separator
                    diskSection
                    separator
                    displaySection
                    separator
                    refreshSection
                }
            }
            .scrollIndicators(.visible)
            separator
            footer
        }
        .frame(width: 360, height: 920)
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

            HStack(spacing: 8) {
                graphAxis(top: "100%", bottom: "0%")
                MonitorGraph(
                    series: [graphHistory.map(\.cpu)],
                    timestamps: graphHistory.map(\.timestamp),
                    colors: [Palette.cyan],
                    ceiling: 1,
                    fillFirst: true
                )
                .accessibilityLabel("CPU history, zero to one hundred percent")
            }
            .frame(height: 76)
            graphTimeAxis(samples: graphHistory, scaleLabel: "100%")

            processList("TOP CPU PROCESSES", processes: store.topCPUProcesses, color: Palette.cyan) {
                String(format: "%.1f%%", $0.cpu)
            }
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
            HStack(spacing: 8) {
                graphAxis(top: "100%", bottom: "0%")
                MonitorGraph(
                    series: [graphHistory.map(\.memory)],
                    timestamps: graphHistory.map(\.timestamp),
                    colors: [Palette.purple],
                    ceiling: 1,
                    fillFirst: true
                )
                .accessibilityLabel("Memory history, zero to one hundred percent")
            }
            .frame(height: 62)
            graphTimeAxis(samples: graphHistory, scaleLabel: "100%")

            HStack {
                Text("\(byteString(snapshot.usedMemory)) used")
                    .foregroundStyle(Palette.secondary)
                Spacer()
                Text("\(byteString(snapshot.totalMemory)) total")
                    .foregroundStyle(Palette.muted)
            }
            .font(.system(size: 11, weight: .medium, design: .monospaced))

            processList("TOP MEMORY PROCESSES", processes: store.topMemoryProcesses, color: Palette.purple) {
                byteString($0.residentBytes)
            }
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

            HStack(spacing: 8) {
                graphAxis(top: "\(byteString(networkCeiling))/s", bottom: "0 B/s")
                MonitorGraph(
                    series: [graphHistory.map(\.download), graphHistory.map(\.upload)],
                    timestamps: graphHistory.map(\.timestamp),
                    colors: [Palette.lime, Palette.orange],
                    ceiling: networkCeiling,
                    fillFirst: false
                )
                .accessibilityLabel("Network history, zero to \(byteString(networkCeiling)) per second")
            }
            .frame(height: 62)
            graphTimeAxis(samples: graphHistory, scaleLabel: "\(byteString(networkCeiling))/s")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
    }

    private var batterySection: some View {
        let battery = snapshot.battery
        let batteryColor = Palette.battery
        return VStack(alignment: .leading, spacing: 13) {
            HStack {
                sectionLabel("BATTERY", symbol: "battery.100percent", color: batteryColor)
                Spacer()
                Text(percent(battery?.level ?? 0))
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Palette.primary)
            }
            HStack(spacing: 8) {
                graphAxis(top: "100%", bottom: "0%")
                MonitorGraph(
                    series: [batteryPoints.map(\.level)],
                    timestamps: batteryPoints.map(\.timestamp),
                    colors: [batteryColor],
                    ceiling: 1,
                    fillFirst: true,
                    timeRange: batteryChartStart...batteryChartEnd,
                    maxPoints: BatteryHistory.maximumPoints,
                    gapThreshold: BatteryHistory.sampleInterval * 3
                )
                .accessibilityLabel("Battery charge history, past 48 hours, zero to one hundred percent")
            }
            .frame(height: 62)
            batteryTimeAxis
            HStack(spacing: 6) {
                Image(systemName: battery?.isCharging == true ? "bolt.fill" :
                      battery?.isPluggedIn == true ? "powerplug.fill" : "battery.100percent")
                    .foregroundStyle(batteryColor)
                Text(battery?.isCharging == true ? "Charging" :
                     battery?.isPluggedIn == true ? "On power adapter" : "On battery")
                    .foregroundStyle(Palette.secondary)
                Spacer()
                Text("RECENT ACTIVITY")
                    .tracking(1)
                    .foregroundStyle(Palette.muted)
            }
            .font(.system(size: 10, weight: .medium, design: .rounded))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
    }

    private var powerSection: some View {
        let power = snapshot.power
        let batteryWatts = power?.batteryWatts
        let batteryColor = batteryWatts.map { $0 < -0.5 ? Palette.orange : Palette.battery } ?? Palette.muted

        return VStack(alignment: .leading, spacing: 13) {
            HStack {
                sectionLabel("POWER FLOW", symbol: "bolt.circle", color: Palette.battery)
                Spacer()
                Text("APPROXIMATE")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(1)
                    .foregroundStyle(Palette.muted)
            }
            HStack(spacing: 8) {
                powerTile("ADAPTER MAX", value: power?.adapterRatingWatts, color: Palette.secondary)
                powerTile("INPUT", value: power?.inputWatts, color: Palette.lime)
                powerTile("SYSTEM", value: power?.systemWatts, color: Palette.cyan)
            }
            HStack(spacing: 7) {
                Image(systemName: batteryWatts.map { $0 < -0.5 ? "battery.100percent" : "bolt.fill" } ?? "battery.100percent")
                    .foregroundStyle(batteryColor)
                Text(batteryWatts.map { $0 < -0.5 ? "Battery draining" : $0 > 0.5 ? "Battery charging" : "Battery idle" } ?? "Battery flow unavailable")
                    .foregroundStyle(Palette.secondary)
                Spacer()
                Text(batteryWatts.map { String(format: "%+.1f W", $0) } ?? "—")
                    .monospacedDigit()
                    .foregroundStyle(batteryColor)
            }
            .font(.system(size: 11, weight: .semibold))
            Text("Adapter max is its rating, not live draw. Battery + charges / − drains.")
                .font(.system(size: 10))
                .foregroundStyle(Palette.muted)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
    }

    private func powerTile(_ title: String, value: Double?, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .tracking(0.5)
                .foregroundStyle(Palette.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(value.map { String(format: "%.1f W", $0) } ?? "—")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(Palette.track.opacity(0.65), in: RoundedRectangle(cornerRadius: 9))
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
            Text("Network lines share a scale based on the latest 30 samples.")
                .font(.system(size: 10))
                .foregroundStyle(Palette.muted)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var refreshSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionLabel("REFRESH RATE", symbol: "timer", color: Palette.cyan)
                Spacer()
                Text("Every \(Int(settings.refreshInterval))s")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Palette.primary)
            }
            Slider(value: $settings.refreshInterval, in: 1...10, step: 1) {
                Text("Refresh interval")
            } minimumValueLabel: {
                Text("1s")
            } maximumValueLabel: {
                Text("10s")
            }
            .tint(Palette.cyan)
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(Palette.muted)
            .accessibilityLabel("Refresh interval")
            .accessibilityValue("\(Int(settings.refreshInterval)) seconds")
            Text("Slower updates use less CPU. Also adjusts process rankings.")
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

    private func processList(
        _ title: String,
        processes: [ProcessUsage],
        color: Color,
        value: @escaping (ProcessUsage) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .tracking(1.1)
                .foregroundStyle(Palette.muted)
                .padding(.bottom, 2)

            if processes.isEmpty {
                Text("Collecting process activity…")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(processes, id: \.pid) { process in
                    HStack(spacing: 8) {
                        Circle().fill(color.opacity(0.75)).frame(width: 4, height: 4)
                        Text(process.name)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(Palette.secondary)
                        Spacer(minLength: 8)
                        Text(value(process))
                            .monospacedDigit()
                            .foregroundStyle(Palette.primary)
                    }
                    .font(.system(size: 11, weight: .medium))
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(process.name), process \(process.pid), \(value(process))")
                }
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.track.opacity(0.65), in: RoundedRectangle(cornerRadius: 10))
    }

    private var batteryTimeAxis: some View {
        HStack(spacing: 8) {
            Text("100%")
                .hidden()
                .fixedSize(horizontal: true, vertical: false)
            HStack {
                Text("48H AGO")
                Spacer()
                Text("24H")
                Spacer()
                Text("NOW")
            }
        }
        .font(.system(size: 9, weight: .medium, design: .monospaced))
        .foregroundStyle(Palette.muted)
        .accessibilityLabel("Battery history from 48 hours ago to now")
    }

    private func graphTimeAxis(samples: [MetricSnapshot], scaleLabel: String) -> some View {
        HStack(spacing: 8) {
            Text(scaleLabel)
                .hidden()
                .fixedSize(horizontal: true, vertical: false)
            HStack {
                Text(GraphTimeline.label(for: samples))
                Spacer()
                Text("NOW")
            }
        }
        .font(.system(size: 9, weight: .medium, design: .monospaced))
        .foregroundStyle(Palette.muted)
        .accessibilityLabel("History from \(GraphTimeline.label(for: samples)) to now")
    }

    private func graphAxis(top: String, bottom: String) -> some View {
        VStack(alignment: .leading) {
            Text(top)
            Spacer()
            Text(bottom)
        }
        .font(.system(size: 9, weight: .medium, design: .monospaced))
        .foregroundStyle(Palette.muted)
        .fixedSize(horizontal: true, vertical: false)
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
    static let battery = Color(red: 1.0, green: 0.79, blue: 0.34)
}

private struct MonitorGraph: View {
    let series: [[Double]]
    let timestamps: [Date]
    let colors: [Color]
    var ceiling: Double? = nil
    var fillFirst = false
    var timeRange: ClosedRange<Date>? = nil
    var maxPoints = 48
    var gapThreshold: TimeInterval? = nil

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
                let values = Array(samples.suffix(maxPoints))
                guard !values.isEmpty else { continue }
                let times = Array(timestamps.suffix(values.count))
                let start = timeRange?.lowerBound ?? times.first ?? .distantPast
                let end = timeRange?.upperBound ?? times.last ?? .distantPast
                let span = end.timeIntervalSince(start)
                let points = values.enumerated().map { offset, value in
                    let progress = times.count == values.count && span > 0
                        ? times[offset].timeIntervalSince(start) / span
                        : Double(offset) / Double(max(values.count - 1, 1))
                    return CGPoint(
                        x: size.width * CGFloat(min(1, max(0, progress))),
                        y: inset + height * (1 - CGFloat(min(max(value.isFinite ? value : 0, 0) / scale, 1)))
                    )
                }
                var segmentStart = 0
                for boundary in 1...points.count {
                    let isGap = boundary < points.count && gapThreshold.map { threshold in
                        times.count == values.count && times[boundary].timeIntervalSince(times[boundary - 1]) > threshold
                    } == true
                    guard isGap || boundary == points.count else { continue }
                    let segment = Array(points[segmentStart..<boundary])
                    segmentStart = boundary
                    guard let first = segment.first, let last = segment.last else { continue }
                    var line = Path()
                    line.move(to: first)
                    for point in segment.dropFirst() { line.addLine(to: point) }
                    if segment.count == 1 && timeRange == nil {
                        line.addLine(to: CGPoint(x: size.width, y: first.y))
                    }
                    if fillFirst && index == 0 && segment.count > 1 {
                        var area = line
                        area.addLine(to: CGPoint(x: last.x, y: size.height))
                        area.addLine(to: CGPoint(x: first.x, y: size.height))
                        area.closeSubpath()
                        context.fill(area, with: .linearGradient(
                            Gradient(colors: [colors[index].opacity(0.28), colors[index].opacity(0.01)]),
                            startPoint: .zero,
                            endPoint: CGPoint(x: 0, y: size.height)
                        ))
                    }
                    context.stroke(line, with: .color(colors[index]), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }
                if let last = points.last {
                    context.fill(Path(ellipseIn: CGRect(x: last.x - 3, y: last.y - 3, width: 6, height: 6)), with: .color(colors[index]))
                }
            }
        }
        .accessibilityHidden(true)
    }
}
