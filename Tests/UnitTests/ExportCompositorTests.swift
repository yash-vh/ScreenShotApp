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
}
