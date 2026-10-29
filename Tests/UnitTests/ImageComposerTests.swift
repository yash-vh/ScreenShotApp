import XCTest
import CoreGraphics
@testable import ScreenMint

final class ImageComposerTests: XCTestCase {
    private func solidImage(width: Int, height: Int, gray: CGFloat = 0.5) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: gray, green: gray, blue: gray, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    /// RGBA of the pixel at (x, y) with a top-left origin
    private func pixel(_ image: CGImage, x: Int, y: Int) -> [UInt8] {
        var data = [UInt8](repeating: 0, count: 4)
        let context = CGContext(
            data: &data, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
        return data
    }

    func testUnstyledDocumentReturnsImageUnchanged() {
        let image = solidImage(width: 100, height: 60)
        let doc = AnnotationDocument(assetId: UUID())
        let result = ImageComposer.shared.compose(image, document: doc)
        XCTAssertEqual(result.width, 100)
        XCTAssertEqual(result.height, 60)
    }

    func testPaddingExpandsCanvasInPixels() {
        let image = solidImage(width: 200, height: 100)
        let doc = AnnotationDocument(assetId: UUID(), pixelsPerPoint: 2.0, backgroundPresetID: "graphite", padding: 20)
        let result = ImageComposer.shared.compose(image, document: doc)
        // 20pt padding at 2x = 40px on every side
        XCTAssertEqual(result.width, 280)
        XCTAssertEqual(result.height, 180)
        // Corner of the canvas is backdrop, not the screenshot
        let corner = pixel(result, x: 2, y: 2)
        XCTAssertEqual(corner[3], 255)
        XCTAssertTrue((30...95).contains(Int(corner[0])), "Graphite backdrop expected at the padded corner, got \(corner)")
        let center = pixel(result, x: 140, y: 90)
        XCTAssertTrue((110...160).contains(Int(center[0])), "Screenshot expected in the middle, got \(center)")
    }

    func testCornerRadiusClipsImageCorners() {
        let image = solidImage(width: 120, height: 120, gray: 1.0)
        let doc = AnnotationDocument(assetId: UUID(), pixelsPerPoint: 1.0, cornerRadius: 30)
        let result = ImageComposer.shared.compose(image, document: doc)
        XCTAssertEqual(result.width, 120)
        XCTAssertEqual(pixel(result, x: 0, y: 0)[3], 0, "Rounded corner should be transparent")
        XCTAssertEqual(pixel(result, x: 60, y: 60)[3], 255, "Center stays opaque")
    }

    func testAllPresetsResolve() {
        XCTAssertFalse(BackgroundPresets.all.isEmpty)
        for preset in BackgroundPresets.all {
            XCTAssertEqual(BackgroundPresets.preset(id: preset.id), preset)
            XCTAssertFalse(preset.colors.isEmpty)
        }
        XCTAssertNil(BackgroundPresets.preset(id: "does-not-exist"))
    }

    func testDesktopBackdropFillsPaddingOpaquely() {
        let image = solidImage(width: 40, height: 40)
        let doc = AnnotationDocument(assetId: UUID(), pixelsPerPoint: 1.0, backgroundPresetID: BackgroundPresets.desktopID, padding: 10)
        let result = ImageComposer.shared.compose(image, document: doc)
        XCTAssertEqual(result.width, 60)
        // Wallpaper, or the fallback gradient when no desktop picture is readable
        XCTAssertEqual(pixel(result, x: 2, y: 2)[3], 255)
    }

    /// Top half red, bottom half blue (top-left origin)
    private func twoToneImage() -> CGImage {
        let context = CGContext(
            data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 2))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 2, width: 4, height: 2))
        return context.makeImage()!
    }

    func testWallpaperAspectFillKeepsOrientationInFlippedContext() {
        let size = 40
        let context = CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        // Same y-down setup as the live canvas
        context.translateBy(x: 0, y: CGFloat(size))
        context.scaleBy(x: 1, y: -1)
        DesktopWallpaper.drawAspectFill(twoToneImage(), in: context, rect: CGRect(x: 0, y: 0, width: size, height: size), flipped: true)
        let result = context.makeImage()!
        XCTAssertGreaterThan(pixel(result, x: 20, y: 5)[0], 200, "Red stays on top")
        XCTAssertGreaterThan(pixel(result, x: 20, y: 35)[2], 200, "Blue stays at the bottom")
    }
}
