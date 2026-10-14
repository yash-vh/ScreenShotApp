import Foundation
import CoreGraphics
import CoreImage

/// High-performance irreversible pixel-level redaction engine.
/// Modifies base image pixels directly via Core Image filters (Gaussian blur & mosaic pixelation)
/// so that redacted areas cannot be recovered from exported assets.
public final class RedactionRenderer: @unchecked Sendable {
    public static let shared = RedactionRenderer()

    private let ciContext: CIContext

    private init() {
        // Create metal-backed CIContext for fast GPU rendering
        if let metalDevice = MTLCreateSystemDefaultDevice() {
            self.ciContext = CIContext(mtlDevice: metalDevice)
        } else {
            self.ciContext = CIContext()
        }
    }

    /// Irreversibly applies Gaussian blur to a specified pixel rectangle within a base CGImage
    public func applyBlur(to baseImage: CGImage, in pixelRect: CGRect, radius: Double = 20.0) -> CGImage {
        guard pixelRect.width >= 1, pixelRect.height >= 1 else { return baseImage }

        let ciImage = CIImage(cgImage: baseImage)

        // Convert top-left pixel coordinates to CoreImage bottom-left coordinates
        let ciY = CGFloat(baseImage.height) - pixelRect.origin.y - pixelRect.height
        let ciRect = CGRect(x: pixelRect.origin.x, y: ciY, width: pixelRect.width, height: pixelRect.height)

        // 1. Crop region to blur
        let targetCrop = ciImage.cropped(to: ciRect)

        // 2. Clamp edges to prevent dark blur fringes
        guard let clamped = CIFilter(name: "CIAffineClamp", parameters: [
            kCIInputImageKey: targetCrop,
            "inputTransform": CGAffineTransform.identity
        ])?.outputImage else {
            return baseImage
        }

        // 3. Apply Gaussian Blur
        guard let blurFilter = CIFilter(name: "CIGaussianBlur", parameters: [
            kCIInputImageKey: clamped,
            kCIInputRadiusKey: radius
        ]), let blurredImage = blurFilter.outputImage?.cropped(to: ciRect) else {
            return baseImage
        }

        // 4. Composite blurred patch back over original image
        guard let compositeFilter = CIFilter(name: "CISourceOverCompositing", parameters: [
            kCIInputImageKey: blurredImage,
            kCIInputBackgroundImageKey: ciImage
        ]), let outputCI = compositeFilter.outputImage else {
            return baseImage
        }

        // 5. Render to a fresh new CGImage (irreversible rasterization)
        guard let outputCG = ciContext.createCGImage(outputCI, from: CGRect(x: 0, y: 0, width: baseImage.width, height: baseImage.height)) else {
            return baseImage
        }

        return outputCG
    }

    /// Irreversibly applies mosaic pixelation to a specified pixel rectangle within a base CGImage
    public func applyPixelation(to baseImage: CGImage, in pixelRect: CGRect, scale: Double = 16.0) -> CGImage {
        guard pixelRect.width >= 1, pixelRect.height >= 1 else { return baseImage }

        let ciImage = CIImage(cgImage: baseImage)

        // Convert top-left pixel coordinates to CoreImage bottom-left coordinates
        let ciY = CGFloat(baseImage.height) - pixelRect.origin.y - pixelRect.height
        let ciRect = CGRect(x: pixelRect.origin.x, y: ciY, width: pixelRect.width, height: pixelRect.height)

        let targetCrop = ciImage.cropped(to: ciRect)

        // Apply CIPixellate to the target rectangle
        guard let pixellateFilter = CIFilter(name: "CIPixellate", parameters: [
            kCIInputImageKey: targetCrop,
            kCIInputCenterKey: CIVector(x: ciRect.midX, y: ciRect.midY),
            kCIInputScaleKey: max(scale, 4.0)
        ]), let pixelatedCrop = pixellateFilter.outputImage?.cropped(to: ciRect) else {
            return baseImage
        }

        // Composite over the original image
        guard let compositeFilter = CIFilter(name: "CISourceOverCompositing", parameters: [
            kCIInputImageKey: pixelatedCrop,
            kCIInputBackgroundImageKey: ciImage
        ]), let outputCI = compositeFilter.outputImage else {
            return baseImage
        }

        guard let outputCG = ciContext.createCGImage(outputCI, from: CGRect(x: 0, y: 0, width: baseImage.width, height: baseImage.height)) else {
            return baseImage
        }

        return outputCG
    }
}
