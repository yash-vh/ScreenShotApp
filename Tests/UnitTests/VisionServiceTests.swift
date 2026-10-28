import XCTest
import AppKit
@testable import ScreenshotApp

final class VisionServiceTests: XCTestCase {
    func testVisionBoundingBoxIsFlippedToTopLeftSpace() {
        // Vision: origin bottom-left. A box hugging the bottom edge must map to the bottom in top-left space.
        let rect = VisionService.normalizedRect(fromVision: CGRect(x: 0.1, y: 0.0, width: 0.5, height: 0.2))
        XCTAssertEqual(rect.origin.x, 0.1, accuracy: 0.0001)
        XCTAssertEqual(rect.origin.y, 0.8, accuracy: 0.0001)
        XCTAssertEqual(rect.width, 0.5, accuracy: 0.0001)
        XCTAssertEqual(rect.height, 0.2, accuracy: 0.0001)
    }

    func testNormalizeTextTrimsCollapsesAndDropsEmptyLines() {
        let text = VisionService.normalizeText(["  Hello    world ", "", "\tSecond\t line  ", "   "])
        XCTAssertEqual(text, "Hello world\nSecond line")
    }

    func testReadingOrderIsTopToBottomThenLeftToRight() {
        let right = RecognizedTextBlock(text: "B", confidence: 1, boundingBox: NormalizedRect(x: 0.6, y: 0.1, width: 0.2, height: 0.05))
        let left = RecognizedTextBlock(text: "A", confidence: 1, boundingBox: NormalizedRect(x: 0.1, y: 0.11, width: 0.2, height: 0.05))
        let below = RecognizedTextBlock(text: "C", confidence: 1, boundingBox: NormalizedRect(x: 0.0, y: 0.5, width: 0.2, height: 0.05))
        let ordered = VisionService.orderedForReading([below, right, left]).map(\.text)
        XCTAssertEqual(ordered, ["A", "B", "C"])
    }

    func testBarcodeURLDetection() {
        let link = DetectedBarcode(payload: "https://example.com/x", symbology: "QR", boundingBox: NormalizedRect(x: 0, y: 0, width: 1, height: 1))
        let plain = DetectedBarcode(payload: "WIFI:S:home;;", symbology: "QR", boundingBox: NormalizedRect(x: 0, y: 0, width: 1, height: 1))
        XCTAssertEqual(link.url?.host, "example.com")
        XCTAssertNil(plain.url)
    }

    func testRecognizesRenderedText() async throws {
        let size = NSSize(width: 800, height: 200)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        ("SCREENSHOT 2026" as NSString).draw(at: NSPoint(x: 40, y: 70), withAttributes: [
            .font: NSFont.systemFont(ofSize: 64, weight: .bold),
            .foregroundColor: NSColor.black
        ])
        image.unlockFocus()
        let cgImage = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))

        let result = try await VisionService.shared.recognize(in: cgImage, recognitionLevel: .fast)
        let first = try XCTUnwrap(result.textBlocks.first)
        XCTAssertTrue(result.fullText.uppercased().contains("SCREENSHOT"), "Got: \(result.fullText)")
        XCTAssertGreaterThan(first.boundingBox.width, 0.3)
        XCTAssertTrue((0...1).contains(first.boundingBox.origin.y))
    }
}
