import XCTest
import CoreGraphics
import CoreSpotlight
@testable import ScreenshotApp

/// Auto-blur detection, text-snapping highlights, scrolling-capture stitching and Spotlight items
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

    // MARK: - Scroll Stitching

    /// A tall "page" of distinct rows with a fixed header and footer, viewed through a window at `offset`
    private static func viewport(offset: Int, height: Int = 120, width: Int = 64, header: Int = 10, footer: Int = 8) -> CGImage {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        // CGContext is y-up: row r from the top lives at y = height - 1 - r
        for r in 0..<height {
            let color: CGColor
            if r < header {
                color = CGColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1)
            } else if r >= height - footer {
                color = CGColor(red: 0.9, green: 0.9, blue: 0.9, alpha: 1)
            } else {
                color = pageRowColor(r - header + offset)
            }
            ctx.setFillColor(color)
            ctx.fill(CGRect(x: 0, y: height - 1 - r, width: width / 2, height: 1))
            // Second half varies too so every row is distinct; header / footer rows are keyed to their own edge
            if r < header {
                ctx.setFillColor(pageRowColor(5_000 + r))
            } else if r >= height - footer {
                ctx.setFillColor(pageRowColor(9_000 + height - r))
            } else {
                ctx.setFillColor(pageRowColor((r - header + offset) * 7 + 3))
            }
            ctx.fill(CGRect(x: width / 2, y: height - 1 - r, width: width / 2, height: 1))
        }
        return ctx.makeImage()!
    }

    private static func pageRowColor(_ row: Int) -> CGColor {
        let v = (row * 37) % 251
        let w = (row * 91) % 241
        return CGColor(red: CGFloat(v) / 255, green: CGFloat(w) / 255, blue: CGFloat((row * 13) % 233) / 255, alpha: 1)
    }

    func testStitchesScrolledFramesWithStickyHeaderAndFooter() throws {
        var stitcher = try XCTUnwrap(ScrollStitcher(firstFrame: Self.viewport(offset: 0)))
        XCTAssertEqual(stitcher.append(Self.viewport(offset: 0)), .unchanged)
        XCTAssertEqual(stitcher.append(Self.viewport(offset: 30)), .appended(rows: 30))
        XCTAssertEqual(stitcher.append(Self.viewport(offset: 75)), .appended(rows: 45))

        let image = try XCTUnwrap(stitcher.makeImage())
        // Frame 120 = 10 header + 102 content + 8 footer; 75 rows of new content scrolled in
        XCTAssertEqual(image.height, 120 + 75)
        XCTAssertEqual(stitcher.acceptedFrames, 3)

        // The stitched content equals a viewport over the whole scrolled page
        let expected = Self.viewport(offset: 0, height: 195, footer: 8)
        let spaceRGB = CGColorSpace(name: CGColorSpace.sRGB)!
        let got = ScrollStitcher.pixels(of: image, width: 64, height: 195, bytesPerRow: 256, colorSpace: spaceRGB)
        let want = ScrollStitcher.pixels(of: expected, width: 64, height: 195, bytesPerRow: 256, colorSpace: spaceRGB)
        let g = try XCTUnwrap(got), w = try XCTUnwrap(want)
        let firstBadRow = (0..<195).first { g[($0 * 256)..<($0 * 256 + 256)] != w[($0 * 256)..<($0 * 256 + 256)] }
        XCTAssertNil(firstBadRow, "First mismatching row")
    }

    func testJumpWithoutOverlapLosesTrack() throws {
        var stitcher = try XCTUnwrap(ScrollStitcher(firstFrame: Self.viewport(offset: 0)))
        XCTAssertEqual(stitcher.append(Self.viewport(offset: 500)), .lostTrack)
        XCTAssertEqual(stitcher.height, 120)
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
}
