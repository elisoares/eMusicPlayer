// Draws the eMusic Player icon and writes Resources/AppIcon.icns.
// Usage: swift Tools/make-icon.swift   (run from the repository root)
import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = root.appendingPathComponent(".build/AppIcon.iconset")
let output = root.appendingPathComponent("Resources/AppIcon.icns")

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r, green: g, blue: b, alpha: a)
}

/// Green → yellow → red, like the retro equalizer.
func ledColor(_ t: CGFloat) -> CGColor {
    let green = (0.10, 0.85, 0.20), yellow = (0.98, 0.84, 0.10), red = (0.96, 0.20, 0.12)
    let (a, b, f) = t < 0.55 ? (green, yellow, t / 0.55) : (yellow, red, (t - 0.55) / 0.45)
    return color(a.0 + (b.0 - a.0) * f, a.1 + (b.1 - a.1) * f, a.2 + (b.2 - a.2) * f)
}

func drawIcon(size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let s = size / 1024

    // macOS icon grid: 824 pt rounded square centered in 1024.
    let tile = CGRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: 185 * s, cornerHeight: 185 * s, transform: nil)

    // Drop shadow under the tile.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10 * s), blur: 28 * s, color: color(0, 0, 0, 0.45))
    ctx.addPath(tilePath)
    ctx.setFillColor(color(0.08, 0.08, 0.10))
    ctx.fillPath()
    ctx.restoreGState()

    // Dark background gradient.
    ctx.saveGState()
    ctx.addPath(tilePath)
    ctx.clip()
    let background = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: [color(0.20, 0.21, 0.26), color(0.05, 0.05, 0.07)] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(background, start: CGPoint(x: 0, y: tile.maxY), end: CGPoint(x: 0, y: tile.minY), options: [])

    // LED equalizer: 7 bars of square segments.
    let levels: [CGFloat] = [0.45, 0.72, 0.95, 0.62, 0.82, 0.5, 0.32]
    let peaks: [CGFloat] = [0.6, 0.85, 1.0, 0.78, 0.92, 0.66, 0.48]
    let area = CGRect(x: tile.minX + 110 * s, y: tile.minY + 105 * s, width: tile.width - 220 * s, height: 420 * s)
    let rows = 12
    let gap = 7 * s
    let segment = (area.height - CGFloat(rows - 1) * gap) / CGFloat(rows)
    let slot = area.width / CGFloat(levels.count)
    let barWidth = slot * 0.74
    for (index, level) in levels.enumerated() {
        let x = area.minX + slot * CGFloat(index) + (slot - barWidth) / 2
        let lit = Int((level * CGFloat(rows)).rounded())
        for row in 0..<rows {
            let rect = CGRect(x: x, y: area.minY + CGFloat(row) * (segment + gap), width: barWidth, height: segment)
            let path = CGPath(roundedRect: rect, cornerWidth: 4 * s, cornerHeight: 4 * s, transform: nil)
            ctx.addPath(path)
            ctx.setFillColor(row < lit ? ledColor(CGFloat(row) / CGFloat(rows - 1)) : color(1, 1, 1, 0.06))
            ctx.fillPath()
        }
        // Peak marker.
        let peakRow = min(rows - 1, max(lit, Int((peaks[index] * CGFloat(rows)).rounded())))
        let peakRect = CGRect(x: x, y: area.minY + CGFloat(peakRow) * (segment + gap), width: barWidth, height: segment)
        ctx.addPath(CGPath(roundedRect: peakRect, cornerWidth: 4 * s, cornerHeight: 4 * s, transform: nil))
        ctx.setFillColor(color(0.92, 0.92, 0.94))
        ctx.fillPath()
    }

    // Music note in the top-left corner.
    let note = NSImage(systemSymbolName: "music.note", accessibilityDescription: nil)!
        .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 150 * s, weight: .bold))!
    let noteSize = note.size
    let noteRect = CGRect(x: tile.minX + 120 * s, y: tile.maxY - 95 * s - noteSize.height, width: noteSize.width, height: noteSize.height)
    let tinted = NSImage(size: noteSize, flipped: false) { rect in
        note.draw(in: rect)
        NSColor.white.set()
        rect.fill(using: .sourceAtop)
        return true
    }
    tinted.draw(in: noteRect)

    // "e" badge next to the note.
    let text = NSAttributedString(string: "e", attributes: [
        .font: NSFont.systemFont(ofSize: 170 * s, weight: .heavy),
        .foregroundColor: NSColor(cgColor: ledColor(0))!,
    ])
    text.draw(at: CGPoint(x: noteRect.maxX + 18 * s, y: noteRect.minY - 30 * s))

    // Subtle top highlight.
    let highlight = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: [color(1, 1, 1, 0.10), color(1, 1, 1, 0)] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(highlight, start: CGPoint(x: 0, y: tile.maxY), end: CGPoint(x: 0, y: tile.midY), options: [])
    ctx.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = CGFloat(base * scale)
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try drawIcon(size: pixels).representation(using: .png, properties: [:])!
            .write(to: iconset.appendingPathComponent(name))
    }
}
try drawIcon(size: 1024).representation(using: .png, properties: [:])!
    .write(to: root.appendingPathComponent("docs/icon.png"))

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try iconutil.run()
iconutil.waitUntilExit()
print(iconutil.terminationStatus == 0 ? "Wrote \(output.path)" : "iconutil failed")
