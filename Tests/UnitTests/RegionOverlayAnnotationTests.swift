import XCTest
import AppKit
@testable import ScreenshotApp

/// The region overlay view is y-up; annotation documents are y-down. Verifies the conversion and keyboard handling.
@MainActor
final class RegionOverlayAnnotationTests: XCTestCase {
    func testOverlayAnnotationsUseTopLeftNormalizedSpace() throws {
        _ = NSApplication.shared
        let screen = try XCTUnwrap(NSScreen.screens.first)
        var completed: (CGRect, RegionCaptureAction)?
        var cancelled = false

        let view = RegionSelectionView(frame: NSRect(x: 0, y: 0, width: 1000, height: 800), screen: screen, screenSnapshot: nil, onComplete: { rect, action in
            completed = (rect, action)
        }, onCancel: {
            cancelled = true
        })
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.contentView = view
        defer { window.close() }

        func mouse(_ type: NSEvent.EventType, _ p: CGPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: p, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        func key(_ chars: String, _ code: UInt16, _ flags: NSEvent.ModifierFlags = []) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code)!
        }
        func drag(_ a: CGPoint, _ b: CGPoint) {
            view.mouseDown(with: mouse(.leftMouseDown, a))
            view.mouseDragged(with: mouse(.leftMouseDragged, CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)))
            view.mouseDragged(with: mouse(.leftMouseDragged, b))
            view.mouseUp(with: mouse(.leftMouseUp, b))
        }

        // Selection spanning y 200...600 (AppKit y-up) and x 100...500
        drag(CGPoint(x: 100, y: 200), CGPoint(x: 500, y: 600))

        // "R" picks the rectangle tool; draw near the TOP of the selection (high y in AppKit coordinates)
        view.keyDown(with: key("r", 15))
        drag(CGPoint(x: 140, y: 580), CGPoint(x: 240, y: 540))

        // ⌘Z / ⇧⌘Z round-trip through performKeyEquivalent
        XCTAssertTrue(view.performKeyEquivalent(with: key("z", 6, .command)))
        XCTAssertTrue(view.performKeyEquivalent(with: key("z", 6, [.command, .shift])))

        // Return copies
        view.keyDown(with: key("\r", 36))
        XCTAssertFalse(cancelled)
        let (_, action) = try XCTUnwrap(completed)
        guard case .copy(let doc) = action else { return XCTFail("Expected copy action") }

        let item = try XCTUnwrap(doc.items.first)
        XCTAssertEqual(item.type, .rectangle)
        XCTAssertEqual(item.bounds.origin.x, 0.1, accuracy: 0.01)
        XCTAssertEqual(item.bounds.origin.y, 0.05, accuracy: 0.01, "Shape drawn at the top must have a small y in y-down space")
        XCTAssertEqual(item.bounds.height, 0.1, accuracy: 0.01)
        XCTAssertEqual(doc.pixelsPerPoint, Double(screen.backingScaleFactor))
    }
}
