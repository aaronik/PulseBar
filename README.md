# PulseBar

**A tiny, beautiful system monitor for your macOS menu bar.**

PulseBar keeps CPU and memory activity in view with two live sparklines. Click the graph to open a dark, compact dashboard with CPU history, memory, network traffic, and storage usage. It is built with AppKit and SwiftUI, has no external dependencies, and runs without a Dock icon. Its waveform app icon also appears in Spotlight.

![PulseBar live resource dashboard](docs/dashboard.png)

## Highlights

- **At-a-glance activity:** teal CPU and purple memory sparklines, plus a live CPU percentage.
- **Make it yours:** toggle the CPU percentage and each CPU, memory, download (lime), and upload (orange) graph line independently in the **MENU BAR** controls. Your choices persist across launches.
- **A meaningful scale:** Unobstructed left-hand axes show 0–100% for CPU, memory, and battery. The network chart shows 0 B/s at the bottom and a live top rate based on recent traffic. CPU, memory, and network show their actual recent span; battery uses a fixed 48H AGO → 24H → NOW axis.
- **Click for detail:** CPU and memory history graphs with live Top 5 process lists, upload/download rates and history, a **48-hour battery charge graph**, charging state, and live **power flow** (adapter rating, input, system load, signed battery charge/discharge) on supported laptops, plus root-volume capacity. The panel scrolls so every section stays accessible.
- **Adjustable refresh:** choose 1–10 seconds with the panel's refresh slider; the choice persists and changes both system and process sampling. Slower updates reduce CPU use.
- **Lightweight and native:** a 60-sample rolling history, an AppKit menu-bar item, and a SwiftUI popover.
- **Private by design:** metrics are collected locally. No account, analytics, network requests, or third-party packages.

## Requirements

macOS 13 or later and the Swift Command Line Tools (`xcode-select --install`). Full Xcode is not required. The build script targets the current Mac's architecture (Apple silicon or Intel).

## Install from source

```sh
git clone https://github.com/aaronik/PulseBar.git
cd PulseBar
./build.sh
open -g build/PulseBar.app
```

PulseBar appears at the right side of the menu bar. Click its graph to open or close the dashboard; click **Quit** in the dashboard to exit. It does not add a Dock icon.

For a permanent installation, move `build/PulseBar.app` to `/Applications` and launch that copy. To start it when you log in, add the installed app in **System Settings → General → Login Items**. Rebuild and replace the installed copy when updating.

> This project currently distributes source code, not a notarized binary. `build.sh` applies an ad-hoc signature to the locally built app.

## Development and checks

```sh
swift build
./build.sh
swiftc -swift-version 6 -target "$(uname -m)-apple-macosx13.0" \
  Sources/PulseBar/Metrics.swift Sources/PulseBar/ProcessSampler.swift \
  Sources/PulseBar/BatterySampler.swift Sources/PulseBar/BatteryHistory.swift \
  Sources/PulseBar/SystemBatteryHistory.swift Sources/PulseBar/PowerSampler.swift \
  Sources/PulseBar/DisplaySettings.swift Sources/PulseBar/GraphTimeline.swift \
  Tests/Smoke.swift -o /tmp/pulsebar-smoke
/tmp/pulsebar-smoke
```

The smoke test takes real samples and checks that metrics are bounded, network rates are nonnegative, and the sampler starts/stops correctly. Full Xcode is needed for XCTest; the standalone smoke test works with Command Line Tools alone.

The bundled `Resources/PulseBar.icns` is generated from `scripts/GenerateIcon.swift`. To regenerate it, run `swift scripts/GenerateIcon.swift Resources/PulseBar.iconset && iconutil -c icns Resources/PulseBar.iconset -o Resources/PulseBar.icns`.

## How it works

| Metric | Source |
| --- | --- |
| CPU | Delta of Mach host CPU ticks (idle versus total) |
| Memory | Physical RAM minus free and inactive VM pages |
| Network | Byte-counter deltas for active, non-loopback interfaces |
| Battery | IOKit current charge/state; read-only system PowerLog history when accessible (omitted on Macs without a battery) |
| Power | IOKit adapter rating and best-effort IORegistry live input/system telemetry; signed battery current × voltage |
| Storage | Root volume capacity and available space |

Readings update at the selected 1–10 second interval; process rankings update at that same interval only while the panel is open. Per-process CPU is the change in process CPU time as a percentage of one logical CPU, so multithreaded processes can exceed 100%. Per-process memory is resident size, not the sum used by all related processes. Some protected processes cannot be read and are omitted. Memory usage is an approximation, **not** Activity Monitor's memory-pressure score. Network traffic through virtual/tunnel interfaces can be counted more than once. CPU, memory, and network graphs retain 60 samples (one to ten minutes, depending on refresh) and reset on restart. Battery first reads macOS's existing PowerLog battery-level history (read-only) to populate the past 48 hours immediately. PowerLog's SQLite schema and access are undocumented and may change or be denied by sandboxing; if unavailable, PulseBar falls back to its own samples every five minutes (or on charging-state changes), retained in Application Support for 48 hours. Fallback history has gaps when the app is not running or the Mac sleeps. Power figures are approximate: adapter max is the negotiated rating, **not** live wall consumption; input and system load come from hardware-dependent IORegistry telemetry and show “—” if unavailable. Battery watts are positive while charging and negative while draining, even on external power.

## License

MIT — see [LICENSE](LICENSE).
