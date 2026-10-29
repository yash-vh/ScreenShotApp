import XCTest
import CoreGraphics
import CoreSpotlight
@testable import ScreenshotApp

/// Auto-blur detection, text-snapping highlights, step numbering and Spotlight items
final class CaptureToolsTests: XCTestCase {
    // MARK: - Sensitive Info

    private func kinds(in text: String) -> [SensitiveInfoKind] {
        SensitiveInfoDetector.matches(in: text).map(\.kind)
    }

    private func matchedText(in text: String) -> [String] {
        SensitiveInfoDetector.matches(in: text).map { String(text[$0.range]) }
    }

    func testDetectsCommonSensitiveInfo() {
        XCTAssertEqual(matchedText(in: "Contact: yash@example.com today"), ["yash@example.com"])
        XCTAssertEqual(kinds(in: "Card 4242 4242 4242 4242 exp 12/30"), [.creditCard])
        XCTAssertEqual(kinds(in: "Server at 192.168.1.20"), [.ipAddress])
        XCTAssertEqual(kinds(in: "SSN 123-45-6789"), [.socialSecurityNumber])
        XCTAssertEqual(kinds(in: "AWS AKIAIOSFODNN7EXAMPLE"), [.secret])
        XCTAssertEqual(kinds(in: "token ghp_abcdefghijklmnopqrstuvwxyz0123456789"), [.secret])
        XCTAssertEqual(matchedText(in: "password: hunter22"), ["hunter22"], "Only the value after the label is hidden")
        XCTAssertFalse(SensitiveInfoDetector.matches(in: "Call +1 (415) 555-0132").isEmpty)
    }

    func testIgnoresOrdinaryText() {
        XCTAssertTrue(SensitiveInfoDetector.matches(in: "Version 14.2 released in 2024 for $19.99").isEmpty)
        XCTAssertTrue(SensitiveInfoDetector.matches(in: "Order 1234 5678 9012 3456").isEmpty, "Fails the Luhn check, so not a card")
        XCTAssertTrue(SensitiveInfoDetector.matches(in: "The quick brown fox jumps over the lazy dog").isEmpty)
    }

    func testLuhn() {
        XCTAssertTrue(SensitiveInfoDetector.passesLuhn("4111-1111-1111-1111"))
        XCTAssertFalse(SensitiveInfoDetector.passesLuhn("4111-1111-1111-1112"))
        XCTAssertFalse(SensitiveInfoDetector.passesLuhn("1234"))
    }

    func testOverlappingMatchesMerge() {
        let text = "api_key = sk-proj-ABCDEFGHIJKLMNOPQRSTUVWX123"
        XCTAssertEqual(SensitiveInfoDetector.matches(in: text).count, 1)
    }

    // MARK: - Text Highlight Snapping

    func testHighlightSnapsToCoveredLines() {
        let lines = [
            NormalizedRect(x: 0.1, y: 0.10, width: 0.8, height: 0.05),
            NormalizedRect(x: 0.1, y: 0.20, width: 0.6, height: 0.05),
            NormalizedRect(x: 0.1, y: 0.40, width: 0.8, height: 0.05)
        ]
        // Rough drag across the first two lines, wider than the second line
        let drag = NormalizedRect(x: 0.2, y: 0.11, width: 0.7, height: 0.12)
        let snapped = TextHighlightSnapper.snap(drag: drag, lines: lines, padding: 0)
        XCTAssertEqual(snapped.count, 2)
        XCTAssertEqual(snapped[0].origin.y, 0.10, accuracy: 0.0001)
        XCTAssertEqual(snapped[0].height, 0.05, accuracy: 0.0001)
        XCTAssertEqual(snapped[1].origin.x + snapped[1].width, 0.7, accuracy: 0.0001, "Clipped to the line's end")
    }

    func testThinStrokeThroughLineCountsAndEmptyAreaFallsBack() {
        let line = NormalizedRect(x: 0.1, y: 0.5, width: 0.5, height: 0.06)
        let stroke = NormalizedRect(x: 0.15, y: 0.525, width: 0.3, height: 0.005)
        XCTAssertEqual(TextHighlightSnapper.snap(drag: stroke, lines: [line]).count, 1)
        let elsewhere = NormalizedRect(x: 0.15, y: 0.8, width: 0.3, height: 0.1)
        XCTAssertTrue(TextHighlightSnapper.snap(drag: elsewhere, lines: [line]).isEmpty)
    }

    // MARK: - Step Numbers

    func testNextStepNumber() {
        var doc = AnnotationDocument(assetId: UUID())
        XCTAssertEqual(doc.nextStepNumber, 1)
        doc.items = [
            AnnotationItem(type: .step, bounds: NormalizedRect(x: 0, y: 0, width: 0.1, height: 0.1), textContent: "1"),
            AnnotationItem(type: .text, bounds: NormalizedRect(x: 0, y: 0, width: 0.1, height: 0.1), textContent: "9"),
            AnnotationItem(type: .step, bounds: NormalizedRect(x: 0, y: 0, width: 0.1, height: 0.1), textContent: "4")
        ]
        XCTAssertEqual(doc.nextStepNumber, 5)
    }

    // MARK: - Spotlight

    func testSpotlightItemCarriesTitleAndText() {
        let asset = ScreenshotAsset(
            title: "Region Capture",
            originalFileURL: URL(fileURLWithPath: "/tmp/YnShot 1.png"),
            pixelWidth: 200, pixelHeight: 100, fileSizeBytes: 10,
            ocrText: "Invoice total 42"
        )
        let item = SpotlightIndexer.item(for: asset)
        XCTAssertEqual(item.uniqueIdentifier, asset.id.uuidString)
        XCTAssertEqual(item.domainIdentifier, SpotlightIndexer.domain)
        XCTAssertEqual(item.attributeSet.title, "Region Capture")
        XCTAssertEqual(item.attributeSet.textContent, "Invoice total 42")
        XCTAssertEqual(item.attributeSet.contentURL, asset.originalFileURL)
    }

    // MARK: - Window Editor Placement

    @MainActor
    func testWindowEditorKeepsWindowPositionWhenItFits() {
        let area = CGRect(x: 1440, y: 0, width: 1920, height: 1050) // second display to the right
        let window = CGRect(x: 1600, y: 200, width: 800, height: 600)
        XCTAssertEqual(CaptureCoordinator.fittedFrame(for: window, imageSize: CGSize(width: 1600, height: 1200), in: area), window)
    }

    @MainActor
    func testWindowEditorFitsOversizedWindowOnScreen() {
        let area = CGRect(x: 0, y: 0, width: 1440, height: 875)
        let window = CGRect(x: -200, y: 100, width: 2000, height: 1000)
        let fitted = CaptureCoordinator.fittedFrame(for: window, imageSize: CGSize(width: 4000, height: 2000), in: area)
        XCTAssertTrue(area.contains(fitted))
        XCTAssertEqual(fitted.width / fitted.height, 2, accuracy: 0.01)
    }
}
