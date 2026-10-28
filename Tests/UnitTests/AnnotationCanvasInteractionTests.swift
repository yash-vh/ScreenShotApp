import XCTest
import AppKit
@testable import ScreenshotApp

/// Drives the editor canvas with synthetic mouse / key events to verify drawing, moving, resizing,
/// undo granularity, and keyboard shortcuts end to end.
@MainActor
final class AnnotationCanvasInteractionTests: XCTestCase {
    private var window: NSWindow!
    private var canvas: AnnotationCanvasView!
    private var manager: UndoRedoManager!
    private var state: EditorState!

    override func setUp() async throws {
        _ = NSApplication.shared
        let image = Self.makeImage(width: 800, height: 600)
        manager = UndoRedoManager(document: AnnotationDocument(assetId: UUID(), pixelsPerPoint: 1))
        state = EditorState(tool: .rectangle)
        canvas = AnnotationCanvasView(frame: NSRect(x: 0, y: 0, width: 848, height: 648), undoRedoManager: manager, state: state, baseImage: image)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 848, height: 648), styleMask: [.titled], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.contentView = canvas
    }

    override func tearDown() async throws {
        window.close()
        window = nil
    }

    private static func makeImage(width: Int, height: Int) -> CGImage {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(gray: 0.8, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()!
    }

    /// Canvas (flipped) point → window event
    private func mouse(_ type: NSEvent.EventType, _ p: CGPoint, clicks: Int = 1, flags: NSEvent.ModifierFlags = []) -> NSEvent {
        let windowPoint = canvas.convert(p, to: nil)
        return NSEvent.mouseEvent(with: type, location: windowPoint, modifierFlags: flags, timestamp: 0,
                                  windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: clicks, pressure: 1)!
    }

    private func drag(from a: CGPoint, to b: CGPoint, steps: Int = 10, flags: NSEvent.ModifierFlags = []) {
        canvas.mouseDown(with: mouse(.leftMouseDown, a, flags: flags))
        for i in 1...steps {
            let t = CGFloat(i) / CGFloat(steps)
            canvas.mouseDragged(with: mouse(.leftMouseDragged, CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t), flags: flags))
        }
        canvas.mouseUp(with: mouse(.leftMouseUp, b, flags: flags))
    }

    private func key(_ chars: String, code: UInt16, flags: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: window.windowNumber,
                         context: nil, characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code)!
    }

    func testImageRectFitsWithMargin() {
        let r = canvas.imageRect
        XCTAssertEqual(r.width, 800, accuracy: 1)
        XCTAssertEqual(r.minX, 24, accuracy: 1)
        XCTAssertEqual(r.minY, 24, accuracy: 1)
    }

    func testDrawMoveUndoIsOneStepPerGesture() throws {
        drag(from: CGPoint(x: 124, y: 124), to: CGPoint(x: 324, y: 224))
        XCTAssertEqual(manager.document.items.count, 1)
        let drawn = try XCTUnwrap(manager.document.items.first)
        XCTAssertEqual(drawn.type, .rectangle)
        XCTAssertEqual(drawn.bounds.origin.x, 0.125, accuracy: 0.01)
        XCTAssertEqual(drawn.bounds.width, 0.25, accuracy: 0.01)

        // Move by grabbing the rectangle's top edge (away from the resize handles) with the select tool
        state.tool = .select
        drag(from: CGPoint(x: 174, y: 124), to: CGPoint(x: 274, y: 224), steps: 25)
        let moved = try XCTUnwrap(manager.document.items.first)
        XCTAssertEqual(moved.bounds.origin.x, 0.25, accuracy: 0.01)
        XCTAssertEqual(moved.bounds.origin.y, drawn.bounds.origin.y + 100.0 / 600.0, accuracy: 0.01)

        manager.undo()
        XCTAssertEqual(manager.document.items.first?.bounds.origin.x ?? 0, drawn.bounds.origin.x, accuracy: 0.001, "Single undo reverts entire move")
        manager.undo()
        XCTAssertTrue(manager.document.items.isEmpty)
        XCTAssertFalse(manager.canUndo)
    }

    func testSelectingItemDoesNotCreateUndoStep() {
        drag(from: CGPoint(x: 124, y: 124), to: CGPoint(x: 324, y: 224))
        state.tool = .select
        canvas.keyDown(with: key("\u{1b}", code: 53)) // deselect
        XCTAssertNil(canvas.selectedItemId)
        canvas.mouseDown(with: mouse(.leftMouseDown, CGPoint(x: 124, y: 150)))
        canvas.mouseUp(with: mouse(.leftMouseUp, CGPoint(x: 124, y: 150)))
        XCTAssertNotNil(canvas.selectedItemId)
        manager.undo()
        XCTAssertTrue(manager.document.items.isEmpty, "Only the draw should be in history, not the selection click")
    }

    func testResizeHandleChangesBounds() throws {
        drag(from: CGPoint(x: 124, y: 124), to: CGPoint(x: 324, y: 224))
        // Rectangle stays selected after drawing; drag its bottom-right handle (inset 4pt outward)
        drag(from: CGPoint(x: 328, y: 228), to: CGPoint(x: 428, y: 328))
        let item = try XCTUnwrap(manager.document.items.first)
        // Edge follows the pointer delta (+100pt each way), without jumping by the handle inset
        XCTAssertEqual(item.bounds.width, 300.0 / 800.0, accuracy: 0.003)
        XCTAssertEqual(item.bounds.height, 200.0 / 600.0, accuracy: 0.003)
        manager.undo()
        XCTAssertEqual(manager.document.items.first?.bounds.width ?? 0, 0.25, accuracy: 0.01)
    }

    func testArrowEndpointDrag() throws {
        state.tool = .arrow
        drag(from: CGPoint(x: 124, y: 124), to: CGPoint(x: 424, y: 124))
        drag(from: CGPoint(x: 424, y: 124), to: CGPoint(x: 424, y: 324))
        let arrow = try XCTUnwrap(manager.document.items.first)
        let end = try XCTUnwrap(arrow.points?.last)
        XCTAssertEqual(end.x, 0.5, accuracy: 0.01)
        XCTAssertEqual(end.y, 0.5, accuracy: 0.01)
        XCTAssertEqual(arrow.points?.first?.x ?? 0, 0.125, accuracy: 0.01, "Start point untouched")
    }

    func testKeyboardShortcuts() throws {
        drag(from: CGPoint(x: 124, y: 124), to: CGPoint(x: 324, y: 224))
        let id = try XCTUnwrap(canvas.selectedItemId)

        // Arrow-key nudges coalesce into one undo step
        for _ in 0..<5 { canvas.keyDown(with: key("\u{F703}", code: 124)) }
        XCTAssertEqual(manager.document.items[0].bounds.origin.x, 105.0 / 800.0, accuracy: 0.002)

        // ⌘D duplicates, ⌫ deletes, ⌘Z restores
        XCTAssertTrue(canvas.performKeyEquivalent(with: key("d", code: 2, flags: .command)))
        XCTAssertEqual(manager.document.items.count, 2)
        canvas.keyDown(with: key("\u{7f}", code: 51))
        XCTAssertEqual(manager.document.items.count, 1)
        XCTAssertTrue(canvas.performKeyEquivalent(with: key("z", code: 6, flags: .command)))
        XCTAssertEqual(manager.document.items.count, 2)
        XCTAssertTrue(canvas.performKeyEquivalent(with: key("z", code: 6, flags: [.command, .shift])))
        XCTAssertEqual(manager.document.items.count, 1)
        XCTAssertTrue(canvas.performKeyEquivalent(with: key("z", code: 6, flags: .command))) // undo delete
        XCTAssertTrue(canvas.performKeyEquivalent(with: key("z", code: 6, flags: .command))) // undo duplicate
        XCTAssertEqual(manager.document.items.count, 1)
        XCTAssertEqual(manager.document.items[0].id, id)
        XCTAssertTrue(canvas.performKeyEquivalent(with: key("z", code: 6, flags: .command))) // undo all nudges
        XCTAssertEqual(manager.document.items[0].bounds.origin.x, 100.0 / 800.0, accuracy: 0.002, "Nudges undone in one step")

        // Single-letter tool shortcuts
        canvas.keyDown(with: key("o", code: 31))
        XCTAssertEqual(state.tool, .ellipse)
        canvas.keyDown(with: key("v", code: 9))
        XCTAssertEqual(state.tool, .select)

        // Esc deselects first
        canvas.mouseDown(with: mouse(.leftMouseDown, CGPoint(x: 124, y: 150)))
        canvas.mouseUp(with: mouse(.leftMouseUp, CGPoint(x: 124, y: 150)))
        XCTAssertNotNil(canvas.selectedItemId)
        canvas.keyDown(with: key("\u{1b}", code: 53))
        XCTAssertNil(canvas.selectedItemId)
    }

    func testStyleChangeAppliesToSelectionAsOneStep() throws {
        state.tool = .blur
        drag(from: CGPoint(x: 124, y: 124), to: CGPoint(x: 324, y: 224))
        for r in stride(from: 22.0, through: 40.0, by: 2.0) { state.blurRadius = r }
        XCTAssertEqual(manager.document.items[0].blurRadius, 40)
        manager.undo()
        XCTAssertEqual(manager.document.items[0].blurRadius, 20, "Slider scrub collapses into one undo step")
    }

    func testDrawingToolCanStartInsideExistingRectangle() {
        drag(from: CGPoint(x: 124, y: 124), to: CGPoint(x: 524, y: 424))
        drag(from: CGPoint(x: 224, y: 224), to: CGPoint(x: 324, y: 324))
        XCTAssertEqual(manager.document.items.count, 2, "Clicking inside an outlined shape with a drawing tool draws, not moves")
    }
}
