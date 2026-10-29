#!/usr/bin/env swift
// Draws the DMG window background: a soft gradient, an install hint and an arrow from the app icon
// to the Applications folder. Icon positions must match Scripts/dmg-settings.py.
//
// Usage: swift Scripts/make-dmg-background.swift <output.tiff>
// Writes 1x and 2x PNGs next to the output and joins them into one HiDPI TIFF.
import AppKit

let width: CGFloat = 660
let height: CGFloat = 420
// Icon centres in Finder's top-left window coordinates (see dmg-settings.py)
let appCenter = CGPoint(x: 180, y: 205)
let applicationsCenter = CGPoint(x: 480, y: 205)

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write("usage: make-dmg-background.swift <output.tiff>\n".data(using: .utf8)!)
    exit(1)
}
let output = URL(fileURLWithPath: CommandLine.arguments[1])

func render(scale: CGFloat) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(width * scale), pixelsHigh: Int(height * scale),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: width, height: height)
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = context
    // Draw in top-left coordinates like Finder
    let cg = context.cgContext
    cg.translateBy(x: 0, y: height)
    cg.scaleBy(x: 1, y: -1)

    // Background: light, so Finder's black icon labels stay readable
    NSGradient(colors: [
        NSColor(srgbRed: 0.97, green: 0.98, blue: 1.00, alpha: 1),
        NSColor(srgbRed: 0.90, green: 0.94, blue: 0.99, alpha: 1)
    ])!.draw(in: NSRect(x: 0, y: 0, width: width, height: height), angle: -90)

    // Soft accent glow behind the icons
    for center in [appCenter, applicationsCenter] {
        let glow = NSRect(x: center.x - 92, y: center.y - 92, width: 184, height: 184)
        NSGradient(colors: [NSColor.white.withAlphaComponent(0.95), NSColor.white.withAlphaComponent(0)])!
            .draw(in: NSBezierPath(ovalIn: glow), relativeCenterPosition: .zero)
    }

    func drawText(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, y: CGFloat) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        // Text draws upright only in an unflipped context
        NSGraphicsContext.saveGraphicsState()
        let flip = NSAffineTransform()
        flip.translateX(by: 0, yBy: height)
        flip.scaleX(by: 1, yBy: -1)
        flip.concat()
        let string = NSAttributedString(string: text, attributes: attributes)
        let textHeight = string.size().height
        string.draw(in: NSRect(x: 0, y: height - y - textHeight, width: width, height: textHeight))
        NSGraphicsContext.restoreGraphicsState()
    }

    drawText("Install ScreenMint", size: 22, weight: .bold, color: NSColor(srgbRed: 0.10, green: 0.12, blue: 0.18, alpha: 1), y: 34)
    drawText("Drag the app onto the Applications folder", size: 13, weight: .regular, color: NSColor(srgbRed: 0.35, green: 0.39, blue: 0.47, alpha: 1), y: 66)

    // Arrow between the icons
    let accent = NSColor(srgbRed: 0.18, green: 0.45, blue: 0.95, alpha: 1)
    let startX = appCenter.x + 82, endX = applicationsCenter.x - 82, y = appCenter.y
    let shaft = NSBezierPath()
    shaft.move(to: CGPoint(x: startX, y: y))
    shaft.line(to: CGPoint(x: endX - 10, y: y))
    shaft.lineWidth = 5
    shaft.lineCapStyle = .round
    let dashes: [CGFloat] = [0.1, 11]
    shaft.setLineDash(dashes, count: 2, phase: 0)
    accent.withAlphaComponent(0.85).setStroke()
    shaft.stroke()
    let head = NSBezierPath()
    head.move(to: CGPoint(x: endX + 4, y: y))
    head.line(to: CGPoint(x: endX - 12, y: y - 11))
    head.line(to: CGPoint(x: endX - 12, y: y + 11))
    head.close()
    accent.setFill()
    head.fill()

    drawText("Then open ScreenMint from Applications and allow Screen Recording when asked.", size: 11.5, weight: .regular, color: NSColor(srgbRed: 0.40, green: 0.44, blue: 0.52, alpha: 1), y: 352)
    drawText("by Yash Nandha", size: 10.5, weight: .medium, color: NSColor(srgbRed: 0.55, green: 0.59, blue: 0.66, alpha: 1), y: 378)

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let base = output.deletingPathExtension()
let png1x = base.appendingPathExtension("png")
let png2x = URL(fileURLWithPath: base.path + "@2x.png")
try! render(scale: 1).write(to: png1x)
try! render(scale: 2).write(to: png2x)

let tiffutil = Process()
tiffutil.executableURL = URL(fileURLWithPath: "/usr/bin/tiffutil")
tiffutil.arguments = ["-cathidpicheck", png1x.path, png2x.path, "-out", output.path]
try! tiffutil.run()
tiffutil.waitUntilExit()
exit(tiffutil.terminationStatus)
