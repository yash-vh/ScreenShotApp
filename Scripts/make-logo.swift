// Draws the ScreenMint logo: a screenshot viewfinder framing a stylized fresh mint leaf
// and capture sparkle on a vibrant macOS mint-emerald squircle.
//
// Usage:
//   swift Scripts/make-logo.swift all
//   # Or individually:
//   swift Scripts/make-logo.swift icon  Branding/ScreenMint-logo.png 1024
//   swift Scripts/make-logo.swift glyph Branding/ScreenMint-menubar.png 36
//
// Then run Scripts/generate-app-icon.sh to refresh the asset catalogs.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255.0,
        green: CGFloat((hex >> 8) & 0xFF) / 255.0,
        blue: CGFloat(hex & 0xFF) / 255.0,
        alpha: alpha
    )
}

/// Viewfinder corner brackets + stylized mint leaf and capture sparkle inside `rect`
func drawScreenMintMark(in context: CGContext, rect: CGRect, lineWidth: CGFloat, isTemplate: Bool) {
    context.saveGState()
    context.setLineWidth(lineWidth)
    context.setLineCap(.round)
    context.setLineJoin(.round)

    // 1. Viewfinder Corner Brackets
    let arm = rect.width * 0.24
    let bend = rect.width * 0.08
    let corners: [(CGPoint, CGFloat, CGFloat)] = [
        (CGPoint(x: rect.minX, y: rect.maxY), 1, -1),
        (CGPoint(x: rect.maxX, y: rect.maxY), -1, -1),
        (CGPoint(x: rect.minX, y: rect.minY), 1, 1),
        (CGPoint(x: rect.maxX, y: rect.minY), -1, 1)
    ]
    for (corner, dx, dy) in corners {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: corner.x, y: corner.y + dy * arm))
        path.addLine(to: CGPoint(x: corner.x, y: corner.y + dy * bend))
        path.addQuadCurve(to: CGPoint(x: corner.x + dx * bend, y: corner.y), control: corner)
        path.addLine(to: CGPoint(x: corner.x + dx * arm, y: corner.y))
        context.addPath(path)
    }
    context.strokePath()

    // 2. Stylized Mint Leaf Emblem in the Center
    let cx = rect.midX
    let cy = rect.midY
    let leafScale = rect.width * 0.29

    context.saveGState()
    context.translateBy(x: cx - rect.width * 0.02, y: cy - rect.height * 0.02)
    context.rotate(by: CGFloat.pi / 4.1) // 44 degrees upward sweep

    let w = leafScale * 0.68
    let h = leafScale * 1.08

    // Organic mint leaf silhouette with pointed apex and rounded shoulder
    let leaf = CGMutablePath()
    leaf.move(to: CGPoint(x: 0, y: -h * 0.95))
    // Right lobe curve
    leaf.addCurve(
        to: CGPoint(x: 0, y: h),
        control1: CGPoint(x: w * 1.18, y: -h * 0.15),
        control2: CGPoint(x: w * 0.82, y: h * 0.65)
    )
    // Left lobe curve
    leaf.addCurve(
        to: CGPoint(x: 0, y: -h * 0.95),
        control1: CGPoint(x: -w * 0.82, y: h * 0.65),
        control2: CGPoint(x: -w * 1.18, y: -h * 0.15)
    )
    leaf.closeSubpath()

    if isTemplate {
        // Monochrome menu bar template
        context.addPath(leaf)
        context.fillPath()

        // Negative-space center stem/vein
        context.setBlendMode(.clear)
        let vein = CGMutablePath()
        vein.move(to: CGPoint(x: 0, y: -h * 0.72))
        vein.addLine(to: CGPoint(x: 0, y: h * 0.72))
        context.setLineWidth(max(1.8, lineWidth * 0.45))
        context.addPath(vein)
        context.strokePath()
    } else {
        // High-resolution icon: filled leaf with elegant negative-space veins
        context.saveGState()
        context.addPath(leaf)
        context.fillPath()
        context.restoreGState()

        // Central precision slit and subtle branching veins
        let vein = CGMutablePath()
        vein.move(to: CGPoint(x: 0, y: -h * 0.72))
        vein.addLine(to: CGPoint(x: 0, y: h * 0.75))

        // Delicately angled leaf veins
        let veinOffsets: [(CGFloat, CGFloat, CGFloat)] = [
            (-0.35, 0.42, 0.12),
            (0.0, 0.45, 0.14),
            (0.35, 0.38, 0.10)
        ]
        for (posRatio, armRatio, riseRatio) in veinOffsets {
            let vy = posRatio * h
            // Right branch
            vein.move(to: CGPoint(x: 0, y: vy))
            vein.addLine(to: CGPoint(x: w * armRatio, y: vy + h * riseRatio))
            // Left branch
            vein.move(to: CGPoint(x: 0, y: vy - h * 0.06))
            vein.addLine(to: CGPoint(x: -w * armRatio, y: vy + h * (riseRatio * 0.85)))
        }

        context.saveGState()
        context.setBlendMode(.destinationOut)
        context.setLineWidth(lineWidth * 0.22)
        context.setLineCap(.round)
        context.addPath(vein)
        context.strokePath()
        context.restoreGState()
    }
    context.restoreGState()

    // 3. Four-point Capture Sparkle (Camera Flash / Mint Freshness)
    let starCx = rect.minX + rect.width * 0.78
    let starCy = rect.minY + rect.height * 0.78
    let starR = rect.width * 0.096

    let star = CGMutablePath()
    star.move(to: CGPoint(x: starCx, y: starCy + starR))
    star.addQuadCurve(to: CGPoint(x: starCx + starR, y: starCy), control: CGPoint(x: starCx, y: starCy))
    star.addQuadCurve(to: CGPoint(x: starCx, y: starCy - starR), control: CGPoint(x: starCx, y: starCy))
    star.addQuadCurve(to: CGPoint(x: starCx - starR, y: starCy), control: CGPoint(x: starCx, y: starCy))
    star.addQuadCurve(to: CGPoint(x: starCx, y: starCy + starR), control: CGPoint(x: starCx, y: starCy))
    star.closeSubpath()

    context.addPath(star)
    context.fillPath()

    context.restoreGState()
}

func renderIcon(size: Int, outputURL: URL) {
    let s = CGFloat(size)
    let context = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)

    // macOS icon squircle: 824pt body centered in 1024 with room for the shadow
    let body = CGRect(x: s * 0.098, y: s * 0.078, width: s * 0.805, height: s * 0.805)
    let cornerR = body.width * 0.225
    let squircle = CGPath(roundedRect: body, cornerWidth: cornerR, cornerHeight: cornerR, transform: nil)

    // Outer shadow
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -s * 0.015), blur: s * 0.035, color: rgb(0x022c22, 0.42))
    context.addPath(squircle)
    context.setFillColor(rgb(0x047857))
    context.fillPath()
    context.restoreGState()

    // Background gradient: fresh mint & emerald
    context.saveGState()
    context.addPath(squircle)
    context.clip()

    let gradientColors = [
        rgb(0x034e3b), // deep forest emerald
        rgb(0x059669), // vibrant emerald
        rgb(0x10B981), // signature mint green
        rgb(0x34D399)  // crisp spearmint highlight
    ] as CFArray
    let locations: [CGFloat] = [0.0, 0.35, 0.72, 1.0]
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: gradientColors, locations: locations)!
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: body.minX, y: body.minY),
        end: CGPoint(x: body.maxX, y: body.maxY),
        options: []
    )

    // Soft top sheen highlight
    let sheenColors = [rgb(0xFFFFFF, 0.28), rgb(0xFFFFFF, 0.0)] as CFArray
    let sheen = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: sheenColors, locations: [0, 1])!
    context.drawLinearGradient(
        sheen,
        start: CGPoint(x: body.midX, y: body.maxY),
        end: CGPoint(x: body.midX, y: body.midY * 1.05),
        options: []
    )
    context.restoreGState()

    // Inner hairline border
    context.addPath(squircle)
    context.setStrokeColor(rgb(0xFFFFFF, 0.24))
    context.setLineWidth(s * 0.0035)
    context.strokePath()

    // Mark layer with ambient drop shadow
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -s * 0.008), blur: s * 0.016, color: rgb(0x023020, 0.45))
    context.beginTransparencyLayer(auxiliaryInfo: nil)
    context.setStrokeColor(rgb(0xFFFFFF, 0.98))
    context.setFillColor(rgb(0xFFFFFF, 0.98))
    drawScreenMintMark(
        in: context,
        rect: body.insetBy(dx: body.width * 0.185, dy: body.width * 0.185),
        lineWidth: s * 0.046,
        isTemplate: false
    )
    context.endTransparencyLayer()
    context.restoreGState()

    let image = context.makeImage()!
    try? FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    let dest = CGImageDestinationCreateWithURL(outputURL as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
    print("Wrote \(outputURL.path) (\(size)×\(size))")
}

func renderGlyph(size: Int, outputURL: URL) {
    let s = CGFloat(size)
    let context = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)

    context.setStrokeColor(rgb(0x000000))
    context.setFillColor(rgb(0x000000))
    drawScreenMintMark(
        in: context,
        rect: CGRect(x: 0, y: 0, width: s, height: s).insetBy(dx: s * 0.06, dy: s * 0.06),
        lineWidth: max(1.8, s * 0.088),
        isTemplate: true
    )

    let image = context.makeImage()!
    try? FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    let dest = CGImageDestinationCreateWithURL(outputURL as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
    print("Wrote \(outputURL.path) (\(size)×\(size))")
}

let args = CommandLine.arguments
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

if args.count == 2 && args[1] == "all" {
    let iconURL = root.appendingPathComponent("Branding/ScreenMint-logo.png")
    let glyphURL = root.appendingPathComponent("Branding/ScreenMint-menubar.png")
    renderIcon(size: 1024, outputURL: iconURL)
    renderGlyph(size: 36, outputURL: glyphURL)
} else if args.count >= 3 && ["icon", "glyph"].contains(args[1]) {
    let mode = args[1]
    let outputURL = URL(fileURLWithPath: args[2])
    let size = args.count > 3 ? Int(args[3]) ?? (mode == "icon" ? 1024 : 36) : (mode == "icon" ? 1024 : 36)
    if mode == "icon" {
        renderIcon(size: size, outputURL: outputURL)
    } else {
        renderGlyph(size: size, outputURL: outputURL)
    }
} else {
    print("Usage: make-logo.swift all | icon output.png [size] | glyph output.png [size]")
    exit(1)
}
