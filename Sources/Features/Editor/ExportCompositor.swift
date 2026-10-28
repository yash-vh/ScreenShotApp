import AppKit
import CoreGraphics

/// Composites the base image, irreversible redactions, vector annotation layers, and presentation styling into a final flattened export.
public final class ExportCompositor: @unchecked Sendable {
    public static let shared = ExportCompositor()

    private init() {}

    /// Renders a flattened CGImage combining the base image with all redactions, annotation layers, and styling
    public func composite(baseImage: CGImage, document: AnnotationDocument) -> CGImage {
        let flattened = flattenAnnotations(baseImage: baseImage, document: document)
        return ImageComposer.shared.compose(flattened, document: document)
    }

    /// Bakes redactions and vector annotations into the base image at its native resolution (no styling)
    public func flattenAnnotations(baseImage: CGImage, document: AnnotationDocument) -> CGImage {
        let imageWidth = baseImage.width
        let imageHeight = baseImage.height

        // 1. Apply true pixel-level redactions first
        let redactedBase = Self.applyRedactions(to: baseImage, items: document.items)

        let vectorItems = document.items.filter { $0.type != .blur && $0.type != .pixelation }
        guard !vectorItems.isEmpty else { return redactedBase }

        // 2. Prepare graphics context for vector annotations
        guard let context = CGContext(
            data: nil,
            width: imageWidth,
            height: imageHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return redactedBase
        }

        let fullRect = CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight)
        context.draw(redactedBase, in: fullRect)

        // 3. Flip to the y-down space annotations are authored in, then render vector layers on top
        context.translateBy(x: 0, y: CGFloat(imageHeight))
        context.scaleBy(x: 1, y: -1)

        let renderer = AnnotationRenderer(imageRect: fullRect, scale: CGFloat(max(document.pixelsPerPoint, 0.1)))
        for item in vectorItems {
            renderer.draw(item, in: context)
        }

        return context.makeImage() ?? redactedBase
    }

    /// Irreversibly applies every blur / pixelation item to the image in document order
    public static func applyRedactions(to image: CGImage, items: [AnnotationItem]) -> CGImage {
        var current = image
        let imgW = Double(image.width)
        let imgH = Double(image.height)

        for item in items where item.type == .blur || item.type == .pixelation {
            let pixelRect = CGRect(
                x: item.bounds.origin.x * imgW,
                y: item.bounds.origin.y * imgH,
                width: item.bounds.width * imgW,
                height: item.bounds.height * imgH
            ).integral

            if item.type == .blur {
                current = RedactionRenderer.shared.applyBlur(to: current, in: pixelRect, radius: item.blurRadius ?? 20.0)
            } else {
                current = RedactionRenderer.shared.applyPixelation(to: current, in: pixelRect, scale: item.blurRadius ?? 16.0)
            }
        }
        return current
    }
}
