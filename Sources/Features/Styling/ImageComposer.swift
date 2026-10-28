import Foundation
import CoreGraphics

/// Composes a flattened screenshot onto a presentation backdrop with padding, rounded corners, and a drop shadow.
public final class ImageComposer: @unchecked Sendable {
    public static let shared = ImageComposer()

    private init() {}

    /// Applies the document's styling to an already-flattened image. Returns the image unchanged when no styling is set.
    public func compose(_ image: CGImage, document: AnnotationDocument) -> CGImage {
        guard document.hasStyling else { return image }

        let scale = CGFloat(max(document.pixelsPerPoint, 0.1))
        let pad = CGFloat(max(document.padding, 0)) * scale
        let corner = CGFloat(max(document.cornerRadius, 0)) * scale
        let shadow = CGFloat(max(document.shadowRadius, 0)) * scale

        let imageW = CGFloat(image.width)
        let imageH = CGFloat(image.height)
        let canvasW = Int((imageW + pad * 2).rounded())
        let canvasH = Int((imageH + pad * 2).rounded())

        guard let context = CGContext(
            data: nil,
            width: canvasW,
            height: canvasH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return image
        }

        let canvasRect = CGRect(x: 0, y: 0, width: canvasW, height: canvasH)
        fillBackground(in: context, rect: canvasRect, document: document)

        let imageRect = CGRect(x: pad, y: pad, width: imageW, height: imageH)
        let cardPath = CGPath(
            roundedRect: imageRect,
            cornerWidth: min(corner, imageW / 2),
            cornerHeight: min(corner, imageH / 2),
            transform: nil
        )

        if shadow > 0 {
            context.saveGState()
            context.setShadow(
                offset: CGSize(width: 0, height: -shadow * 0.35),
                blur: shadow,
                color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.45)
            )
            context.addPath(cardPath)
            context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
            context.fillPath()
            context.restoreGState()
        }

        context.saveGState()
        context.addPath(cardPath)
        context.clip()
        context.draw(image, in: imageRect)
        context.restoreGState()

        return context.makeImage() ?? image
    }

    private func fillBackground(in context: CGContext, rect: CGRect, document: AnnotationDocument) {
        if BackgroundPresets.fillBackdrop(id: document.backgroundPresetID, in: context, rect: rect) {
            return
        } else if let color = document.backgroundColor {
            context.setFillColor(CGColor(red: color.red, green: color.green, blue: color.blue, alpha: color.alpha))
            context.fill(rect)
        }
    }

    /// Fills `rect` with a preset (solid, or a top-left → bottom-right gradient in a y-up context)
    public static func fill(preset: BackgroundPreset, in context: CGContext, rect: CGRect, flipped: Bool = false) {
        let colors = preset.cgColors
        guard colors.count > 1 else {
            if let solid = colors.first {
                context.setFillColor(solid)
                context.fill(rect)
            }
            return
        }

        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: nil) else { return }
        let start = CGPoint(x: rect.minX, y: flipped ? rect.minY : rect.maxY)
        let end = CGPoint(x: rect.maxX, y: flipped ? rect.maxY : rect.minY)
        context.saveGState()
        context.clip(to: rect)
        context.drawLinearGradient(gradient, start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        context.restoreGState()
    }
}
