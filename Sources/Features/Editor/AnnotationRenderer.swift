import AppKit
import CoreGraphics

/// Shared vector renderer used by the editor canvas, the capture overlay, and the export compositor.
///
/// Draws into a y-down (flipped) CoreGraphics context so normalized top-left annotation geometry
/// maps directly onto `imageRect`. Callers rendering into a y-up context must flip the CTM first.
public struct AnnotationRenderer {
    /// Rect occupied by the base image in the target context's y-down coordinate space
    public let imageRect: CGRect
    /// Multiplier converting annotation points (stroke widths, font sizes) into target units
    public let scale: CGFloat

    public init(imageRect: CGRect, scale: CGFloat) {
        self.imageRect = imageRect
        self.scale = scale
    }

    // MARK: - Coordinate Mapping

    public func point(for p: NormalizedPoint) -> CGPoint {
        CGPoint(x: imageRect.minX + p.x * imageRect.width, y: imageRect.minY + p.y * imageRect.height)
    }

    public func rect(for r: NormalizedRect) -> CGRect {
        CGRect(
            x: imageRect.minX + r.origin.x * imageRect.width,
            y: imageRect.minY + r.origin.y * imageRect.height,
            width: r.width * imageRect.width,
            height: r.height * imageRect.height
        )
    }

    // MARK: - Text Metrics

    public static func font(ofSize size: CGFloat) -> NSFont {
        NSFont.systemFont(ofSize: max(size, 1), weight: .semibold)
    }

    public static func textAttributes(fontSize: CGFloat, color: AnnotationColor) -> [NSAttributedString.Key: Any] {
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
        shadow.shadowOffset = NSSize(width: 0, height: -max(fontSize / 22, 0.5))
        shadow.shadowBlurRadius = max(fontSize / 10, 1)
        return [
            .font: font(ofSize: fontSize),
            .foregroundColor: NSColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: color.alpha),
            .shadow: shadow
        ]
    }

    /// Size of rendered text at the given font size (points in, points out)
    public static func textSize(_ text: String, fontSize: CGFloat) -> CGSize {
        let bounding = (text as NSString).boundingRect(
            with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font(ofSize: fontSize)]
        )
        return CGSize(width: ceil(bounding.width) + 4, height: ceil(bounding.height) + 2)
    }

    // MARK: - Drawing

    /// Draws a vector annotation. Blur and pixelation are raster effects and are skipped here.
    public func draw(_ item: AnnotationItem, in context: CGContext) {
        let rect = rect(for: item.bounds)
        let color = item.strokeColor
        let strokeCG = CGColor(red: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
        let lineWidth = CGFloat(item.strokeWidth) * scale

        context.saveGState()
        defer { context.restoreGState() }

        context.setStrokeColor(strokeCG)
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        switch item.type {
        case .rectangle:
            if let fill = item.fillColor {
                context.setFillColor(CGColor(red: fill.red, green: fill.green, blue: fill.blue, alpha: fill.alpha))
                context.fill(rect)
            }
            context.stroke(rect)

        case .ellipse:
            if let fill = item.fillColor {
                context.setFillColor(CGColor(red: fill.red, green: fill.green, blue: fill.blue, alpha: fill.alpha))
                context.fillEllipse(in: rect)
            }
            context.strokeEllipse(in: rect)

        case .arrow:
            let pts = item.points ?? []
            let start = pts.count >= 2 ? point(for: pts[0]) : CGPoint(x: rect.minX, y: rect.minY)
            let end = pts.count >= 2 ? point(for: pts[1]) : CGPoint(x: rect.maxX, y: rect.maxY)
            Self.drawArrow(from: start, to: end, color: strokeCG, lineWidth: lineWidth, in: context)

        case .highlight:
            context.setFillColor(strokeCG.copy(alpha: 0.35) ?? strokeCG)
            context.fill(rect)

        case .freehand:
            guard let pts = item.points, pts.count > 1 else { return }
            Self.addSmoothPath(pts.map { point(for: $0) }, to: context)
            context.strokePath()

        case .text:
            guard let text = item.textContent, !text.isEmpty else { return }
            let attrs = Self.textAttributes(fontSize: CGFloat(item.fontSize ?? 22) * scale, color: color)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
            (text as NSString).draw(
                with: CGRect(x: rect.minX + 2 * scale, y: rect.minY + 1 * scale, width: .greatestFiniteMagnitude, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attrs
            )
            NSGraphicsContext.restoreGraphicsState()

        case .blur, .pixelation:
            break
        }
    }

    public static func drawArrow(from start: CGPoint, to end: CGPoint, color: CGColor, lineWidth: CGFloat, in context: CGContext) {
        let length = hypot(end.x - start.x, end.y - start.y)
        guard length > 1 else { return }

        let angle = atan2(end.y - start.y, end.x - start.x)
        let headLength = min(max(lineWidth * 3.5, 12), length)
        let headAngle: CGFloat = .pi / 6

        // Stop the shaft inside the head so round caps never poke through the tip
        let bodyEnd = CGPoint(x: end.x - headLength * 0.6 * cos(angle), y: end.y - headLength * 0.6 * sin(angle))
        context.move(to: start)
        context.addLine(to: bodyEnd)
        context.strokePath()

        let p1 = CGPoint(x: end.x - headLength * cos(angle - headAngle), y: end.y - headLength * sin(angle - headAngle))
        let p2 = CGPoint(x: end.x - headLength * cos(angle + headAngle), y: end.y - headLength * sin(angle + headAngle))
        context.setFillColor(color)
        context.move(to: end)
        context.addLine(to: p1)
        context.addLine(to: p2)
        context.closePath()
        context.fillPath()
    }

    /// Adds a quadratic-smoothed polyline through `points` to the current path
    public static func addSmoothPath(_ points: [CGPoint], to context: CGContext) {
        guard let first = points.first else { return }
        context.move(to: first)
        guard points.count > 2 else {
            points.dropFirst().forEach { context.addLine(to: $0) }
            return
        }
        for i in 1..<(points.count - 1) {
            let mid = CGPoint(x: (points[i].x + points[i + 1].x) / 2, y: (points[i].y + points[i + 1].y) / 2)
            context.addQuadCurve(to: mid, control: points[i])
        }
        context.addLine(to: points[points.count - 1])
    }
}
