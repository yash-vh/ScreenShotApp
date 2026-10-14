import AppKit
import CoreGraphics

/// Composites the base image, irreversible redactions, and vector annotation layers into a final flattened export.
public final class ExportCompositor: @unchecked Sendable {
    public static let shared = ExportCompositor()

    private init() {}

    /// Renders a flattened CGImage combining the base image with all annotation layers and redactions
    public func composite(baseImage: CGImage, document: AnnotationDocument) -> CGImage {
        let imageWidth = baseImage.width
        let imageHeight = baseImage.height

        // 1. Apply true pixel-level redactions first
        var redactedBase = baseImage
        for item in document.items {
            let pixelRect = CGRect(
                x: item.bounds.origin.x * Double(imageWidth),
                y: item.bounds.origin.y * Double(imageHeight),
                width: item.bounds.width * Double(imageWidth),
                height: item.bounds.height * Double(imageHeight)
            )

            if item.type == .blur {
                redactedBase = RedactionRenderer.shared.applyBlur(to: redactedBase, in: pixelRect, radius: item.blurRadius ?? 20.0)
            } else if item.type == .pixelation {
                redactedBase = RedactionRenderer.shared.applyPixelation(to: redactedBase, in: pixelRect, scale: item.blurRadius ?? 16.0)
            }
        }

        // 2. Prepare graphics context for vector annotations
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

        guard let context = CGContext(
            data: nil,
            width: imageWidth,
            height: imageHeight,
            bitsPerComponent: 8,
            bytesPerRow: imageWidth * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            return redactedBase
        }

        // Draw redacted base image
        let fullRect = CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight)
        context.draw(redactedBase, in: fullRect)

        // 3. Render vector annotation layers on top
        for item in document.items {
            // Skip blur and pixelation since they were permanently baked into the base image
            if item.type == .blur || item.type == .pixelation { continue }

            let pixelRect = CGRect(
                x: item.bounds.origin.x * Double(imageWidth),
                y: item.bounds.origin.y * Double(imageHeight),
                width: item.bounds.width * Double(imageWidth),
                height: item.bounds.height * Double(imageHeight)
            )

            renderAnnotationItem(item, in: pixelRect, imageSize: CGSize(width: imageWidth, height: imageHeight), context: context)
        }

        guard let flattened = context.makeImage() else {
            return redactedBase
        }

        return flattened
    }

    private func renderAnnotationItem(_ item: AnnotationItem, in rect: CGRect, imageSize: CGSize, context: CGContext) {
        context.saveGState()

        let strokeCG = CGColor(
            red: CGFloat(item.strokeColor.red),
            green: CGFloat(item.strokeColor.green),
            blue: CGFloat(item.strokeColor.blue),
            alpha: CGFloat(item.strokeColor.alpha)
        )
        context.setStrokeColor(strokeCG)
        context.setLineWidth(CGFloat(item.strokeWidth))
        context.setLineCap(.round)
        context.setLineJoin(.round)

        if let fill = item.fillColor {
            let fillCG = CGColor(
                red: CGFloat(fill.red),
                green: CGFloat(fill.green),
                blue: CGFloat(fill.blue),
                alpha: CGFloat(fill.alpha)
            )
            context.setFillColor(fillCG)
        }

        switch item.type {
        case .rectangle:
            if item.fillColor != nil {
                context.fill(rect)
            }
            context.stroke(rect)

        case .ellipse:
            if item.fillColor != nil {
                context.fillEllipse(in: rect)
            }
            context.strokeEllipse(in: rect)

        case .arrow:
            drawArrow(in: rect, strokeColor: strokeCG, lineWidth: CGFloat(item.strokeWidth), context: context)

        case .highlight:
            let highlightColor = CGColor(
                red: CGFloat(item.strokeColor.red),
                green: CGFloat(item.strokeColor.green),
                blue: CGFloat(item.strokeColor.blue),
                alpha: 0.35
            )
            context.setFillColor(highlightColor)
            context.fill(rect)

        case .freehand:
            if let points = item.points, points.count > 1 {
                let cgPoints = points.map {
                    CGPoint(x: $0.x * Double(imageSize.width), y: $0.y * Double(imageSize.height))
                }
                context.move(to: cgPoints[0])
                for i in 1..<cgPoints.count {
                    context.addLine(to: cgPoints[i])
                }
                context.strokePath()
            }

        case .text:
            if let text = item.textContent, !text.isEmpty {
                drawText(text, in: rect, color: strokeCG, fontSize: CGFloat(item.fontSize ?? 24.0))
            }

        default:
            break
        }

        context.restoreGState()
    }

    private func drawArrow(in rect: CGRect, strokeColor: CGColor, lineWidth: CGFloat, context: CGContext) {
        let start = CGPoint(x: rect.minX, y: rect.minY)
        let end = CGPoint(x: rect.maxX, y: rect.maxY)

        // Draw line body
        context.move(to: start)
        context.addLine(to: end)
        context.strokePath()

        // Calculate arrowhead angle
        let angle = atan2(end.y - start.y, end.x - start.x)
        let headLength: CGFloat = max(lineWidth * 3.5, 16.0)
        let headAngle: CGFloat = .pi / 6 // 30 degrees

        let p1 = CGPoint(
            x: end.x - headLength * cos(angle - headAngle),
            y: end.y - headLength * sin(angle - headAngle)
        )
        let p2 = CGPoint(
            x: end.x - headLength * cos(angle + headAngle),
            y: end.y - headLength * sin(angle + headAngle)
        )

        context.setFillColor(strokeColor)
        context.move(to: end)
        context.addLine(to: p1)
        context.addLine(to: p2)
        context.closePath()
        context.fillPath()
    }

    private func drawText(_ text: String, in rect: CGRect, color: CGColor, fontSize: CGFloat) {
        let font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
        let nsColor = NSColor(cgColor: color) ?? .red
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: nsColor
        ]
        let attrString = NSAttributedString(string: text, attributes: attributes)
        attrString.draw(in: rect)
    }
}
