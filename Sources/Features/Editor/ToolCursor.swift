import AppKit

/// Cursors for the annotation canvas: a precise dot at the hot spot with a small badge of the active
/// tool beside it (instead of a crosshair), plus native resize cursors for selection handles.
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
        let cursor = makeBadgeCursor(symbol: tool.systemIcon)
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

    /// 32 pt cursor: ringed dot (hot spot) top-left, tool badge bottom-right
    private static func makeBadgeCursor(symbol: String) -> NSCursor {
        let size = NSSize(width: 32, height: 32)
        let hotSpot = NSPoint(x: 7, y: 7)
        let image = NSImage(size: size, flipped: true) { _ in
            // Precise point: dark ring + white core reads on any background
            let dot = NSRect(x: hotSpot.x - 3.5, y: hotSpot.y - 3.5, width: 7, height: 7)
            NSColor.black.withAlphaComponent(0.75).setFill()
            NSBezierPath(ovalIn: dot.insetBy(dx: -1.2, dy: -1.2)).fill()
            NSColor.white.setFill()
            NSBezierPath(ovalIn: dot).fill()

            // Tool badge
            let badge = NSRect(x: 13, y: 13, width: 17, height: 17)
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
            shadow.shadowBlurRadius = 2
            shadow.shadowOffset = NSSize(width: 0, height: -1)
            shadow.set()
            NSColor.white.setFill()
            NSBezierPath(roundedRect: badge, xRadius: 5, yRadius: 5).fill()
            NSGraphicsContext.restoreGraphicsState()
            NSColor.black.withAlphaComponent(0.15).setStroke()
            let outline = NSBezierPath(roundedRect: badge.insetBy(dx: 0.25, dy: 0.25), xRadius: 5, yRadius: 5)
            outline.lineWidth = 0.5
            outline.stroke()

            if let glyph = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 9.5, weight: .semibold)) {
                let g = glyph.size
                let rect = NSRect(x: badge.midX - g.width / 2, y: badge.midY - g.height / 2, width: g.width, height: g.height)
                let tinted = NSImage(size: g, flipped: false) { inner in
                    glyph.draw(in: inner)
                    NSColor.black.withAlphaComponent(0.85).set()
                    inner.fill(using: .sourceAtop)
                    return true
                }
                tinted.draw(in: rect)
            }
            return true
        }
        return NSCursor(image: image, hotSpot: hotSpot)
    }
}
