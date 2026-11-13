// Draws the eMusic Player icon (a vinyl record whose grooves light up like an LED
// spectrum, with a green "e" on a small LCD in the middle) and writes Resources/AppIcon.icns
// plus docs/icon.png.
// Usage: swift Tools/make-icon.swift   (run from the repository root)
import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = root.appendingPathComponent(".build/AppIcon.iconset")
let output = root.appendingPathComponent("Resources/AppIcon.icns")
let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r, green: g, blue: b, alpha: a)
}

func gradient(_ colors: [CGColor]) -> CGGradient {
    CGGradient(colorsSpace: sRGB, colors: colors as CFArray, locations: nil)!
}

/// Green → yellow → red, like the retro equalizer.
func led(_ t: CGFloat) -> CGColor {
    let g = (0.10, 0.85, 0.20), y = (0.98, 0.84, 0.10), r = (0.96, 0.20, 0.12)
    let (a, b, f) = t < 0.55 ? (g, y, t / 0.55) : (y, r, (t - 0.55) / 0.45)
    return rgb(a.0 + (b.0 - a.0) * f, a.1 + (b.1 - a.1) * f, a.2 + (b.2 - a.2) * f)
}

func drawIcon(pixels: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(pixels), pixelsHigh: Int(pixels), bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    // Draw in a 1024 design space.
    ctx.scaleBy(x: pixels / 1024, y: pixels / 1024)

    // macOS icon grid: 824 pt rounded square centered in 1024.
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: rgb(0, 0, 0, 0.4))
    ctx.addPath(tilePath)
    ctx.setFillColor(rgb(0, 0, 0))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(tilePath)
    ctx.clip()
    ctx.drawLinearGradient(gradient([rgb(0.20, 0.21, 0.26), rgb(0.05, 0.05, 0.07)]),
                           start: CGPoint(x: 0, y: tile.maxY), end: CGPoint(x: 0, y: tile.minY), options: [])

    // Vinyl record with grooves and a soft shine.
    let c = CGPoint(x: 512, y: 512)
    let radius: CGFloat = 350
    let disc = CGRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 30, color: rgb(0, 0, 0, 0.45))
    ctx.addEllipse(in: disc)
    ctx.setFillColor(rgb(0.07, 0.07, 0.08))
    ctx.fillPath()
    ctx.restoreGState()
    for r in stride(from: radius - 20, to: 162, by: -15) {
        ctx.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        ctx.setStrokeColor(rgb(1, 1, 1, 0.07))
        ctx.setLineWidth(3)
        ctx.strokePath()
    }
    ctx.saveGState()
    ctx.addEllipse(in: disc)
    ctx.clip()
    ctx.drawLinearGradient(gradient([rgb(1, 1, 1, 0.16), rgb(1, 1, 1, 0)]),
                           start: CGPoint(x: c.x - radius * 0.8, y: c.y + radius * 0.8), end: c, options: [])
    ctx.restoreGState()

    // Grooves lit as a circular LED spectrum.
    let segments = 40
    let rings = 7
    for i in 0..<segments {
        let level = 0.3 + 0.7 * abs(sin(CGFloat(i) * 0.55) * cos(CGFloat(i) * 0.21))
        let lit = Int((level * CGFloat(rings)).rounded())
        let a0 = CGFloat(i) / CGFloat(segments) * .pi * 2 + 0.02
        let a1 = CGFloat(i + 1) / CGFloat(segments) * .pi * 2 - 0.035
        for ring in 0..<rings {
            ctx.addArc(center: c, radius: 175 + CGFloat(ring) * 23, startAngle: a0, endAngle: a1, clockwise: false)
            ctx.setLineWidth(15)
            ctx.setLineCap(.butt)
            ctx.setStrokeColor(ring < lit ? led(CGFloat(ring) / CGFloat(rings - 1)) : rgb(1, 1, 1, 0.05))
            ctx.strokePath()
        }
    }

    // LCD center with the green "e".
    let screen = CGRect(x: c.x - 110, y: c.y - 110, width: 220, height: 220)
    ctx.addEllipse(in: screen.insetBy(dx: -8, dy: -8))
    ctx.setFillColor(rgb(0.13, 0.13, 0.15))
    ctx.fillPath()
    ctx.addEllipse(in: screen)
    ctx.setFillColor(rgb(0.03, 0.06, 0.04))
    ctx.fillPath()
    var font = NSFont.systemFont(ofSize: 190, weight: .heavy)
    if let rounded = font.fontDescriptor.withDesign(.rounded) { font = NSFont(descriptor: rounded, size: 190) ?? font }
    let letter = NSAttributedString(string: "e", attributes: [
        .font: font,
        .foregroundColor: NSColor(red: 0.25, green: 1, blue: 0.4, alpha: 1),
    ])
    let size = letter.size()
    letter.draw(at: CGPoint(x: c.x - size.width / 2, y: c.y + 12 - size.height / 2))

    ctx.restoreGState()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try drawIcon(pixels: CGFloat(base * scale)).representation(using: .png, properties: [:])!
            .write(to: iconset.appendingPathComponent(name))
    }
}
try drawIcon(pixels: 1024).representation(using: .png, properties: [:])!
    .write(to: root.appendingPathComponent("docs/app-icon.png"))

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try iconutil.run()
iconutil.waitUntilExit()
print(iconutil.terminationStatus == 0 ? "Wrote \(output.path)" : "iconutil failed")
