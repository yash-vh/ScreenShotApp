// Draws the SyncShot logo: a viewfinder framing two "sync" arrows on a blue–violet macOS squircle.
//
//   swift Scripts/make-logo.swift icon  Branding/SyncShot-logo.png        # 1024×1024 app icon source
//   swift Scripts/make-logo.swift glyph Branding/SyncShot-menubar.png 36  # monochrome menu bar template
//
// Then run Scripts/generate-app-icon.sh Branding/SyncShot-logo.png to refresh the asset catalog.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let arguments = CommandLine.arguments
guard arguments.count >= 3, ["icon", "glyph"].contains(arguments[1]) else {
    print("Usage: make-logo.swift icon|glyph output.png [pixel size]")
    exit(1)
}
let mode = arguments[1]
let output = URL(fileURLWithPath: arguments[2])
let size = arguments.count > 3 ? Int(arguments[3]) ?? 1024 : (mode == "icon" ? 1024 : 36)

let s = CGFloat(size)
let context = CGContext(
    data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
)!
context.setAllowsAntialiasing(true)
context.setShouldAntialias(true)

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// Viewfinder corners + two sync arrows inside `rect`, stroked with the current stroke color
func drawMark(in rect: CGRect, lineWidth: CGFloat) {
    context.setLineWidth(lineWidth)
    context.setLineCap(.round)
    context.setLineJoin(.round)

    // Viewfinder corner brackets
    let arm = rect.width * 0.26
    let corners: [(CGPoint, CGFloat, CGFloat)] = [
        (CGPoint(x: rect.minX, y: rect.maxY), 1, -1),
        (CGPoint(x: rect.maxX, y: rect.maxY), -1, -1),
        (CGPoint(x: rect.minX, y: rect.minY), 1, 1),
        (CGPoint(x: rect.maxX, y: rect.minY), -1, 1)
    ]
    let bend = rect.width * 0.09
    for (corner, dx, dy) in corners {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: corner.x, y: corner.y + dy * arm))
        path.addLine(to: CGPoint(x: corner.x, y: corner.y + dy * bend))
        path.addQuadCurve(to: CGPoint(x: corner.x + dx * bend, y: corner.y), control: corner)
        path.addLine(to: CGPoint(x: corner.x + dx * arm, y: corner.y))
        context.addPath(path)
    }
    context.strokePath()

    // Two sync arcs, each ending in an arrowhead
    let center = CGPoint(x: rect.midX, y: rect.midY)
    let radius = rect.width * 0.2
    let head = lineWidth * 1.25
    for start in [CGFloat.pi * 0.2, CGFloat.pi * 1.2] {
        let end = start + .pi * 0.62
        let arc = CGMutablePath()
        arc.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: false)
        context.addPath(arc)
        context.strokePath()

        // Arrowhead whose base sits on the arc end, pointing along the arc
        let base = CGPoint(x: center.x + radius * cos(end), y: center.y + radius * sin(end))
        let tangent = CGPoint(x: -sin(end), y: cos(end))
        let normal = CGPoint(x: cos(end), y: sin(end))
        let arrow = CGMutablePath()
        arrow.move(to: CGPoint(x: base.x + tangent.x * head * 1.15, y: base.y + tangent.y * head * 1.15))
        arrow.addLine(to: CGPoint(x: base.x + normal.x * head, y: base.y + normal.y * head))
        arrow.addLine(to: CGPoint(x: base.x - normal.x * head, y: base.y - normal.y * head))
        arrow.closeSubpath()
        context.addPath(arrow)
        context.fillPath()
    }
}

if mode == "icon" {
    // macOS icon grid: 824pt body centered in 1024 with room for the shadow
    let body = CGRect(x: s * 0.098, y: s * 0.078, width: s * 0.805, height: s * 0.805)
    let squircle = CGPath(roundedRect: body, cornerWidth: body.width * 0.225, cornerHeight: body.width * 0.225, transform: nil)

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.03, color: rgb(0x000000, 0.35))
    context.addPath(squircle)
    context.setFillColor(rgb(0x3B5BFD))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(squircle)
    context.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [rgb(0x38BDF8), rgb(0x4F6BFF), rgb(0x7C3AED)] as CFArray, locations: [0, 0.5, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: body.minX, y: body.maxY), end: CGPoint(x: body.maxX, y: body.minY), options: [])
    // Soft top sheen
    let sheen = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [rgb(0xFFFFFF, 0.22), rgb(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(sheen, start: CGPoint(x: body.midX, y: body.maxY), end: CGPoint(x: body.midX, y: body.midY), options: [])
    context.restoreGState()

    // Inner hairline for definition on light backgrounds
    context.addPath(squircle)
    context.setStrokeColor(rgb(0xFFFFFF, 0.18))
    context.setLineWidth(s * 0.004)
    context.strokePath()

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -s * 0.006), blur: s * 0.012, color: rgb(0x1E1B4B, 0.35))
    // One transparency layer so the shadow is cast by the whole mark, not each stroke
    context.beginTransparencyLayer(auxiliaryInfo: nil)
    context.setStrokeColor(rgb(0xFFFFFF))
    context.setFillColor(rgb(0xFFFFFF))
    drawMark(in: body.insetBy(dx: body.width * 0.2, dy: body.width * 0.2), lineWidth: s * 0.047)
    context.endTransparencyLayer()
    context.restoreGState()
} else {
    // Template glyph: black on transparent; macOS tints it for the menu bar
    context.setStrokeColor(rgb(0x000000))
    context.setFillColor(rgb(0x000000))
    drawMark(in: CGRect(x: 0, y: 0, width: s, height: s).insetBy(dx: s * 0.08, dy: s * 0.08), lineWidth: max(1, s * 0.085))
}

let image = context.makeImage()!
try? FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, image, nil)
CGImageDestinationFinalize(destination)
print("Wrote \(output.path) (\(size)×\(size))")
