import XCTest
import CoreGraphics
@testable import ScreenMint

final class RedactionRendererTests: XCTestCase {
    private func createPatternImage(width: Int = 100, height: Int = 100) -> CGImage? {
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

        // Draw alternating black and white stripes
        for i in 0..<10 {
            context.setFillColor(i % 2 == 0 ? CGColor(gray: 1.0, alpha: 1.0) : CGColor(gray: 0.0, alpha: 1.0))
            context.fill(CGRect(x: i * 10, y: 0, width: 10, height: 100))
        }

        return context.makeImage()
    }

    func testApplyBlurPreservesDimensions() {
        guard let base = createPatternImage(width: 100, height: 100) else {
            XCTFail("Failed to create base pattern image")
            return
        }

        let blurred = RedactionRenderer.shared.applyBlur(
            to: base,
            in: CGRect(x: 20, y: 20, width: 60, height: 60),
            radius: 15.0
        )

        XCTAssertEqual(blurred.width, 100)
        XCTAssertEqual(blurred.height, 100)
    }

    func testApplyPixelationPreservesDimensions() {
        guard let base = createPatternImage(width: 100, height: 100) else {
            XCTFail("Failed to create base pattern image")
            return
        }

        let pixelated = RedactionRenderer.shared.applyPixelation(
            to: base,
            in: CGRect(x: 10, y: 10, width: 80, height: 80),
            scale: 12.0
        )

        XCTAssertEqual(pixelated.width, 100)
        XCTAssertEqual(pixelated.height, 100)
    }
}
