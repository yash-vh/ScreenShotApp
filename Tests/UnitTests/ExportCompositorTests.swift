import XCTest
import CoreGraphics
@testable import ScreenshotApp

final class ExportCompositorTests: XCTestCase {
    private func createBaseImage(width: Int = 400, height: Int = 300) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else { return nil }

        context.setFillColor(CGColor(red: 0.9, green: 0.9, blue: 0.9, alpha: 1.0))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    func testExportCompositorProducesFlattenedImage() {
        guard let base = createBaseImage(width: 400, height: 300) else {
            XCTFail("Failed to create base image")
            return
        }

        let doc = AnnotationDocument(
            assetId: UUID(),
            items: [
                AnnotationItem(type: .rectangle, bounds: NormalizedRect(x: 0.1, y: 0.1, width: 0.3, height: 0.3), strokeColor: .red),
                AnnotationItem(type: .arrow, bounds: NormalizedRect(x: 0.5, y: 0.5, width: 0.4, height: 0.4), strokeColor: .blue),
                AnnotationItem(type: .blur, bounds: NormalizedRect(x: 0.2, y: 0.2, width: 0.2, height: 0.2))
            ]
        )

        let composited = ExportCompositor.shared.composite(baseImage: base, document: doc)

        XCTAssertEqual(composited.width, 400)
        XCTAssertEqual(composited.height, 300)
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

    func testAnnotationsKeepTopLeftOrientation() throws {
        let base = try XCTUnwrap(createBaseImage(width: 200, height: 200))
        // Highlight covering the TOP quarter of the image in normalized (y-down) space
        let doc = AnnotationDocument(
            assetId: UUID(),
            items: [AnnotationItem(type: .highlight, bounds: NormalizedRect(x: 0, y: 0, width: 1, height: 0.25), strokeColor: .blue)]
        )
        let result = ExportCompositor.shared.composite(baseImage: base, document: doc)

        let top = pixel(result, x: 100, y: 10)
        let bottom = pixel(result, x: 100, y: 190)
        XCTAssertGreaterThan(Int(top[2]) - Int(top[0]), 30, "Top band should be tinted blue")
        XCTAssertLessThan(abs(Int(bottom[2]) - Int(bottom[0])), 4, "Bottom must stay untouched (no vertical flip)")
    }

    func testStrokeWidthScalesWithPixelsPerPoint() throws {
        let base = try XCTUnwrap(createBaseImage(width: 200, height: 200))
        // A 4pt line at 2x must be ~8px thick: a pixel 3px off the center line is still painted
        let doc = AnnotationDocument(
            assetId: UUID(),
            items: [AnnotationItem(type: .arrow, bounds: NormalizedRect(x: 0.1, y: 0.5, width: 0.6, height: 0), strokeColor: .red, strokeWidth: 4, points: [NormalizedPoint(x: 0.1, y: 0.5), NormalizedPoint(x: 0.7, y: 0.5)])],
            pixelsPerPoint: 2.0
        )
        let result = ExportCompositor.shared.composite(baseImage: base, document: doc)
        let nearLine = pixel(result, x: 60, y: 103)
        XCTAssertGreaterThan(Int(nearLine[0]) - Int(nearLine[1]), 100, "Expected red stroke 3px from the line center")
    }

    func testTextIsRenderedIntoExport() throws {
        let base = try XCTUnwrap(createBaseImage(width: 300, height: 120))
        let doc = AnnotationDocument(
            assetId: UUID(),
            items: [AnnotationItem(type: .text, bounds: NormalizedRect(x: 0.05, y: 0.1, width: 0.9, height: 0.8), strokeColor: .black, textContent: "MMMM", fontSize: 48)]
        )
        let result = ExportCompositor.shared.composite(baseImage: base, document: doc)

        var darkPixels = 0
        for x in stride(from: 10, to: 290, by: 4) {
            for y in stride(from: 10, to: 110, by: 4) where pixel(result, x: x, y: y)[0] < 80 {
                darkPixels += 1
            }
        }
        XCTAssertGreaterThan(darkPixels, 10, "Text annotation must be drawn into the flattened export")
    }
}
