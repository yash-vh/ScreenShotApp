import AppKit

/// Cursors for the annotation canvas, in the style of macOS's own: the system pointer with a small tool
/// badge (like Finder's copy cursor) for shapes and redaction, and pen / highlighter shaped cursors whose
/// tip is the hot spot for freehand tools.
@MainActor
enum ToolCursor {
    private static var cache: [EditorTool: NSCursor] = [:]

    /// Cursor for drawing with `tool` over the image
    static func cursor(for tool: EditorTool) -> NSCursor {
        switch tool {
        case .select: return .arrow
        case .text: return .iBeam
        default: break
        }
        if let cached = cache[tool] { return cached }
        let cursor: NSCursor
        switch tool {
        case .freehand: cursor = makeInstrumentCursor(symbol: "pencil")
        case .highlight: cursor = makeInstrumentCursor(symbol: "highlighter")
        default: cursor = makePointerBadgeCursor(symbol: tool.systemIcon)
        }
        cache[tool] = cursor
        return cursor
    }

    /// Edge / corner resize cursor (diagonal arrows on macOS 15+, closest straight arrows before)
    static func resize(_ position: ResizePosition) -> NSCursor {
        if #available(macOS 15.0, *) {
            let frame: NSCursor.FrameResizePosition
            switch position {
            case .top: frame = .top
            case .bottom: frame = .bottom
            case .left: frame = .left
            case .right: frame = .right
            case .topLeft: frame = .topLeft
            case .topRight: frame = .topRight
            case .bottomLeft: frame = .bottomLeft
            case .bottomRight: frame = .bottomRight
            }
            return NSCursor.frameResize(position: frame, directions: .all)
        }
        switch position {
        case .left, .right: return .resizeLeftRight
        case .top, .bottom: return .resizeUpDown
        default: return .closedHand
        }
    }

    enum ResizePosition {
        case top, bottom, left, right, topLeft, topRight, bottomLeft, bottomRight
    }

    /// macOS-style arrow pointer (hot spot at its tip) with a dark rounded badge holding the tool glyph
    private static func makePointerBadgeCursor(symbol: String) -> NSCursor {
        let size = NSSize(width: 32, height: 32)
        let tip = NSPoint(x: 4, y: 3)
        let image = NSImage(size: size, flipped: true) { _ in
            // Classic pointer outline, drawn rather than copied from NSCursor.arrow so it renders anywhere
            let points: [CGPoint] = [(0, 0), (0, 16.5), (3.9, 12.8), (6.6, 19.2), (9.2, 18.1), (6.6, 11.9), (11.8, 11.9)]
                .map { CGPoint(x: tip.x + $0.0, y: tip.y + $0.1) }
            let pointer = NSBezierPath()
            pointer.move(to: points[0])
            points.dropFirst().forEach { pointer.line(to: $0) }
            pointer.close()
            pointer.lineJoinStyle = .round
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
            shadow.shadowBlurRadius = 1.5
            shadow.shadowOffset = NSSize(width: 0, height: -1)
            shadow.set()
            NSColor.white.setStroke()
            pointer.lineWidth = 2.6
            pointer.stroke()
            NSGraphicsContext.restoreGraphicsState()
            NSColor.black.setFill()
            pointer.fill()

            let badge = NSRect(x: 14, y: 15, width: 16, height: 16)
            NSColor.white.setFill()
            NSBezierPath(roundedRect: badge.insetBy(dx: -1.2, dy: -1.2), xRadius: 5, yRadius: 5).fill()
            NSColor(white: 0.13, alpha: 1).setFill()
            NSBezierPath(roundedRect: badge, xRadius: 4, yRadius: 4).fill()
            drawGlyph(symbol, pointSize: 9, weight: .bold, color: .white, centeredIn: badge)
            return true
        }
        return NSCursor(image: image, hotSpot: tip)
    }

    /// Pen-like cursor: the tool glyph in black with a white outline, its writing tip (lower left) at the hot spot
    private static func makeInstrumentCursor(symbol: String) -> NSCursor {
        let size = NSSize(width: 26, height: 26)
        let glyphRect = NSRect(x: 2, y: 2, width: 22, height: 22)
        let image = NSImage(size: size, flipped: false) { _ in
            // White halo so the cursor reads on dark and light pixels alike
            for dx in stride(from: -1.5, through: 1.5, by: 0.75) {
                for dy in stride(from: -1.5, through: 1.5, by: 0.75) where dx * dx + dy * dy <= 2.4 {
                    drawGlyph(symbol, pointSize: 17, weight: .medium, color: .white, centeredIn: glyphRect.offsetBy(dx: dx, dy: dy))
                }
            }
            drawGlyph(symbol, pointSize: 17, weight: .medium, color: .black, centeredIn: glyphRect)
            return true
        }
        let tip = tipLocation(of: symbol, pointSize: 17, weight: .medium, in: glyphRect)
        // NSCursor hot spots are top-left based
        return NSCursor(image: image, hotSpot: NSPoint(x: tip.x, y: size.height - tip.y))
    }

    private static func symbolImage(_ symbol: String, pointSize: CGFloat, weight: NSFont.Weight) -> NSImage? {
        NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight))
    }

    private static func glyphFrame(_ glyph: NSImage, centeredIn rect: NSRect) -> NSRect {
        NSRect(x: rect.midX - glyph.size.width / 2, y: rect.midY - glyph.size.height / 2, width: glyph.size.width, height: glyph.size.height)
    }

    private static func drawGlyph(_ symbol: String, pointSize: CGFloat, weight: NSFont.Weight, color: NSColor, centeredIn rect: NSRect) {
        guard let glyph = symbolImage(symbol, pointSize: pointSize, weight: weight) else { return }
        let tinted = NSImage(size: glyph.size, flipped: false) { inner in
            glyph.draw(in: inner)
            color.set()
            inner.fill(using: .sourceAtop)
            return true
        }
        tinted.draw(in: glyphFrame(glyph, centeredIn: rect))
    }

    /// Lowest-leftmost opaque pixel of the glyph (pencil and highlighter both write at their lower-left end),
    /// in the unflipped coordinates of the cursor image
    private static func tipLocation(of symbol: String, pointSize: CGFloat, weight: NSFont.Weight, in rect: NSRect) -> NSPoint {
        guard let glyph = symbolImage(symbol, pointSize: pointSize, weight: weight) else { return NSPoint(x: rect.minX, y: rect.minY) }
        let frame = glyphFrame(glyph, centeredIn: rect)
        let scale: CGFloat = 4
        let width = Int(frame.width * scale), height = Int(frame.height * scale)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
            return NSPoint(x: frame.minX, y: frame.minY)
        }
        rep.size = frame.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        glyph.draw(in: NSRect(origin: .zero, size: frame.size))
        NSGraphicsContext.restoreGraphicsState()
        let opaque = { (x: Int, y: Int) in (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 }
        // Skip a baseline stroke under the tool (the highlighter glyph has one): rows mostly filled edge to edge
        let isBaseline = { (y: Int) in (0..<width).filter { opaque($0, y) }.count > width * 6 / 10 }
        // Bitmap rows run top to bottom; score favours bottom and left equally
        var best: (score: Int, x: Int, y: Int)?
        for y in 0..<height where !isBaseline(y) {
            for x in 0..<width where opaque(x, y) {
                let score = (height - 1 - y) + x
                if best == nil || score < best!.score { best = (score, x, y) }
            }
        }
        guard let best else { return NSPoint(x: frame.minX, y: frame.minY) }
        return NSPoint(x: frame.minX + CGFloat(best.x) / scale, y: frame.minY + CGFloat(height - 1 - best.y) / scale)
    }
}
