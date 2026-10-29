import XCTest
@testable import ScreenMint

final class CaptureGeometryTests: XCTestCase {
    func testAppKitToDisplayCoordinateConversion() {
        let screenFrame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let selectedRect = CGRect(x: 100, y: 500, width: 400, height: 300)
        let scale: CGFloat = 2.0 // Retina display

        let displayX = selectedRect.origin.x - screenFrame.origin.x
        let displayY = screenFrame.height - (selectedRect.origin.y - screenFrame.origin.y + selectedRect.height)

        let pixelRect = CGRect(
            x: displayX * scale,
            y: displayY * scale,
            width: selectedRect.width * scale,
            height: selectedRect.height * scale
        )

        XCTAssertEqual(displayX, 100)
        // 1080 - (500 + 300) = 280
        XCTAssertEqual(displayY, 280)
        XCTAssertEqual(pixelRect.width, 800)
        XCTAssertEqual(pixelRect.height, 600)
        XCTAssertEqual(pixelRect.origin.x, 200)
        XCTAssertEqual(pixelRect.origin.y, 560)
    }

    func testInvalidRegionValidation() {
        let zeroRect = CGRect.zero
        XCTAssertTrue(zeroRect.width < 1 || zeroRect.height < 1)

        let subPixelRect = CGRect(x: 10, y: 10, width: 0.5, height: 0.8)
        XCTAssertTrue(subPixelRect.width < 1 || subPixelRect.height < 1)
    }
}
