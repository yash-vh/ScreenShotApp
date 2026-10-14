import XCTest
import CoreGraphics
@testable import ScreenshotApp

final class ScreenCaptureServiceTests: XCTestCase {
    private func createTestCGImage(width: Int = 200, height: Int = 100) -> CGImage? {
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

        context.setFillColor(CGColor(red: 0.2, green: 0.6, blue: 0.9, alpha: 1.0))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    func testSaveImagePNG() async throws {
        guard let image = createTestCGImage(width: 150, height: 100) else {
            XCTFail("Failed to create test CGImage")
            return
        }

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_capture_\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        try await ScreenCaptureService.shared.saveImage(image, format: .png, to: tempURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: tempURL.path))
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: tempURL.path)[.size] as? Int64) ?? 0
        XCTAssertGreaterThan(fileSize, 0)
    }

    func testSaveImageJPEG() async throws {
        guard let image = createTestCGImage(width: 150, height: 100) else {
            XCTFail("Failed to create test CGImage")
            return
        }

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_capture_\(UUID().uuidString).jpg")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        try await ScreenCaptureService.shared.saveImage(image, format: .jpeg, jpegQuality: 0.8, to: tempURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: tempURL.path))
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: tempURL.path)[.size] as? Int64) ?? 0
        XCTAssertGreaterThan(fileSize, 0)
    }
}
