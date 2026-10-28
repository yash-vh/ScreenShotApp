import XCTest
import AppKit
@testable import ScreenshotApp

/// The region overlay hosts the same canvas/toolbar/undo stack as the editor. Verifies the session wiring,
/// the y-down document space, shared shortcuts, and capture actions.
@MainActor
final class RegionOverlayAnnotationTests: XCTestCase {
    func testOverlayUsesSharedEditorSession() throws {
        _ = NSApplication.shared
        let screen = try XCTUnwrap(NSScreen.screens.first)
        var completed: (CGRect, RegionCaptureAction)?
        var cancelled = false

        let view = RegionSelectionView(frame: NSRect(x: 0, y: 0, width: 1000, height: 800), screen: screen, screenSnapshot: nil, onComplete: { rect, action, _ in
            completed = (rect, action)
        }, onCancel: {
            cancelled = true
        })
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.contentView = view
        defer { window.close() }

        func mouse(_ type: NSEvent.EventType, _ windowPoint: CGPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: windowPoint, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        func key(_ chars: String, _ code: UInt16, _ flags: NSEvent.ModifierFlags = []) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code)!
        }

        // 1. Select y 200...600 (AppKit y-up), x 100...500
        view.mouseDown(with: mouse(.leftMouseDown, CGPoint(x: 100, y: 200)))
        view.mouseDragged(with: mouse(.leftMouseDragged, CGPoint(x: 300, y: 400)))
        view.mouseDragged(with: mouse(.leftMouseDragged, CGPoint(x: 500, y: 600)))
        view.mouseUp(with: mouse(.leftMouseUp, CGPoint(x: 500, y: 600)))

        let canvas = try XCTUnwrap(view.canvas, "Selecting a region starts the shared annotation canvas")
        XCTAssertEqual(canvas.presentation, .embedded)
        XCTAssertEqual(canvas.frame, CGRect(x: 100, y: 200, width: 400, height: 400))
        XCTAssertEqual(view.editorState.tool, .arrow, "Same default tool as the editor")

        // 2. Same tool shortcuts as the editor: "R" → rectangle; draw near the TOP of the selection
        canvas.keyDown(with: key("r", 15))
        XCTAssertEqual(view.editorState.tool, .rectangle)
        func canvasPoint(_ p: CGPoint) -> CGPoint { canvas.convert(p, to: nil) } // canvas is flipped (y-down)
        canvas.mouseDown(with: mouse(.leftMouseDown, canvasPoint(CGPoint(x: 40, y: 20))))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, canvasPoint(CGPoint(x: 90, y: 40))))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, canvasPoint(CGPoint(x: 140, y: 60))))
        canvas.mouseUp(with: mouse(.leftMouseUp, canvasPoint(CGPoint(x: 140, y: 60))))
        XCTAssertEqual(view.undoRedoManager.document.items.count, 1)

        // 3. ⌘Z / ⇧⌘Z reach the shared undo stack through the overlay's key-equivalent chain
        XCTAssertTrue(view.performKeyEquivalent(with: key("z", 6, .command)))
        XCTAssertTrue(view.undoRedoManager.document.items.isEmpty)
        XCTAssertTrue(view.performKeyEquivalent(with: key("z", 6, [.command, .shift])))
        XCTAssertEqual(view.undoRedoManager.document.items.count, 1)

        // 4. Return (no text selected) copies, exactly like the old overlay
        canvas.keyDown(with: key("\r", 36))
        XCTAssertFalse(cancelled)
        let (rect, action) = try XCTUnwrap(completed)
        XCTAssertEqual(rect.size, CGSize(width: 400, height: 400))
        guard case .copy(let doc) = action else { return XCTFail("Expected copy action") }

        let item = try XCTUnwrap(doc.items.first)
        XCTAssertEqual(item.type, .rectangle)
        XCTAssertEqual(item.bounds.origin.x, 0.1, accuracy: 0.01)
        XCTAssertEqual(item.bounds.origin.y, 0.05, accuracy: 0.01, "Shape drawn at the top must have a small y in y-down space")
        XCTAssertEqual(item.bounds.height, 0.1, accuracy: 0.01)
        XCTAssertEqual(doc.pixelsPerPoint, Double(screen.backingScaleFactor))
    }

    func testEscapeBeforeSelectionCancels() throws {
        _ = NSApplication.shared
        let screen = try XCTUnwrap(NSScreen.screens.first)
        var cancelled = false
        let view = RegionSelectionView(frame: NSRect(x: 0, y: 0, width: 400, height: 300), screen: screen, screenSnapshot: nil, onComplete: { _, _, _ in }, onCancel: { cancelled = true })
        view.keyDown(with: NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!)
        XCTAssertTrue(cancelled)
    }
}
