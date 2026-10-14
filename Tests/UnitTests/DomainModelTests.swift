import XCTest
@testable import ScreenshotApp

final class DomainModelTests: XCTestCase {
    func testNormalizedGeometryClamping() {
        let outOfBoundsPoint = NormalizedPoint(x: -0.5, y: 1.5)
        XCTAssertEqual(outOfBoundsPoint.x, 0.0)
        XCTAssertEqual(outOfBoundsPoint.y, 1.0)

        let rect = NormalizedRect(x: 0.8, y: 0.8, width: 0.5, height: 0.5)
        XCTAssertEqual(rect.origin.x, 0.8)
        XCTAssertEqual(rect.origin.y, 0.8)
        XCTAssertLessThanOrEqual(rect.origin.x + rect.width, 1.0)
        XCTAssertLessThanOrEqual(rect.origin.y + rect.height, 1.0)
    }

    func testScreenshotAssetSerialization() throws {
        let asset = ScreenshotAsset(
            title: "Test Capture",
            originalFileURL: URL(fileURLWithPath: "/tmp/test.png"),
            pixelWidth: 2560,
            pixelHeight: 1440,
            fileSizeBytes: 1048576,
            ocrText: "Sample OCR text",
            mediaType: .image
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(asset)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ScreenshotAsset.self, from: data)

        XCTAssertEqual(decoded.id, asset.id)
        XCTAssertEqual(decoded.title, "Test Capture")
        XCTAssertEqual(decoded.pixelWidth, 2560)
        XCTAssertEqual(decoded.pixelHeight, 1440)
        XCTAssertEqual(decoded.ocrText, "Sample OCR text")
        XCTAssertEqual(decoded.mediaType, .image)
    }

    func testAnnotationDocumentSerialization() throws {
        let item = AnnotationItem(
            type: .arrow,
            bounds: NormalizedRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
            strokeColor: .red,
            strokeWidth: 4.0
        )
        let doc = AnnotationDocument(
            assetId: UUID(),
            items: [item],
            backgroundColor: .white,
            padding: 16.0,
            cornerRadius: 12.0,
            shadowRadius: 8.0
        )

        let data = try JSONEncoder().encode(doc)
        let decoded = try JSONDecoder().decode(AnnotationDocument.self, from: data)

        XCTAssertEqual(decoded.items.count, 1)
        XCTAssertEqual(decoded.items[0].type, .arrow)
        XCTAssertEqual(decoded.padding, 16.0)
        XCTAssertEqual(decoded.cornerRadius, 12.0)
    }
}
