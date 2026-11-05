import AppKit
import Foundation

// Run with: swift scripts/GenerateIcon.swift Resources/PulseBar.iconset
let directory = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Resources/PulseBar.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

let sizes: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)
]

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: red, green: green, blue: blue, alpha: alpha)
}

func render(_ pixels: Int) -> Data {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
        isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let context = NSGraphicsContext.current!.cgContext
    context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    context.setShouldAntialias(true)

    let tile = CGRect(x: 62, y: 62, width: 900, height: 900)
    let rounded = NSBezierPath(roundedRect: tile, xRadius: 212, yRadius: 212)
    rounded.addClip()
    let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [color(0.11, 0.17, 0.24).cgColor, color(0.055, 0.075, 0.13).cgColor] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(gradient, start: CGPoint(x: 100, y: 960), end: CGPoint(x: 950, y: 50), options: [])

    // Three quiet grid lines give the waveform a visual scale.
    for fraction in [0.27, 0.5, 0.73] {
        let path = NSBezierPath()
        let y = 180 + 660 * fraction
        path.move(to: CGPoint(x: 144, y: y))
        path.line(to: CGPoint(x: 880, y: y))
        path.lineWidth = 3
        color(0.76, 0.89, 0.99, 0.11).setStroke()
        path.stroke()
    }

    let shadow = NSShadow()
    shadow.shadowColor = color(0.17, 0.86, 0.94, 0.48)
    shadow.shadowBlurRadius = 36
    shadow.set()

    // The mark is a continuous pulse graph, recognizable even at Spotlight sizes.
    let pulse = NSBezierPath()
    pulse.move(to: CGPoint(x: 154, y: 459))
    pulse.line(to: CGPoint(x: 292, y: 459))
    pulse.curve(to: CGPoint(x: 359, y: 502), controlPoint1: CGPoint(x: 325, y: 459), controlPoint2: CGPoint(x: 333, y: 502))
    pulse.line(to: CGPoint(x: 435, y: 690))
    pulse.line(to: CGPoint(x: 540, y: 307))
    pulse.line(to: CGPoint(x: 620, y: 549))
    pulse.curve(to: CGPoint(x: 685, y: 459), controlPoint1: CGPoint(x: 638, y: 508), controlPoint2: CGPoint(x: 662, y: 459))
    pulse.line(to: CGPoint(x: 870, y: 459))
    pulse.lineWidth = 48
    pulse.lineCapStyle = .round
    pulse.lineJoinStyle = .round
    color(0.24, 0.86, 0.92).setStroke()
    pulse.stroke()

    NSShadow().set()
    let dot = NSBezierPath(ovalIn: CGRect(x: 837, y: 426, width: 66, height: 66))
    color(0.84, 0.94, 0.33).setFill()
    dot.fill()

    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}

for (name, pixels) in sizes {
    try render(pixels).write(to: directory.appendingPathComponent(name))
}
