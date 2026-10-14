import XCTest
@testable import ScreenshotApp

@MainActor
final class UndoRedoTests: XCTestCase {
    func testUndoRedoStackOperations() {
        let initialDoc = AnnotationDocument(assetId: UUID())
        let manager = UndoRedoManager(document: initialDoc)

        XCTAssertFalse(manager.canUndo)
        XCTAssertFalse(manager.canRedo)
        XCTAssertEqual(manager.document.items.count, 0)

        // Add Item 1
        let item1 = AnnotationItem(
            type: .arrow,
            bounds: NormalizedRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2)
        )
        manager.addItem(item1)

        XCTAssertTrue(manager.canUndo)
        XCTAssertFalse(manager.canRedo)
        XCTAssertEqual(manager.document.items.count, 1)

        // Add Item 2
        let item2 = AnnotationItem(
            type: .rectangle,
            bounds: NormalizedRect(x: 0.4, y: 0.4, width: 0.3, height: 0.3)
        )
        manager.addItem(item2)
        XCTAssertEqual(manager.document.items.count, 2)

        // Undo once
        manager.undo()
        XCTAssertEqual(manager.document.items.count, 1)
        XCTAssertTrue(manager.canRedo)

        // Undo twice (back to empty)
        manager.undo()
        XCTAssertEqual(manager.document.items.count, 0)
        XCTAssertFalse(manager.canUndo)

        // Redo once
        manager.redo()
        XCTAssertEqual(manager.document.items.count, 1)

        // Redo twice (both items restored)
        manager.redo()
        XCTAssertEqual(manager.document.items.count, 2)
        XCTAssertFalse(manager.canRedo)
    }

    func testClearAllItems() {
        let initialDoc = AnnotationDocument(assetId: UUID())
        let manager = UndoRedoManager(document: initialDoc)

        manager.addItem(AnnotationItem(type: .rectangle, bounds: NormalizedRect(x: 0, y: 0, width: 0.5, height: 0.5)))
        manager.addItem(AnnotationItem(type: .ellipse, bounds: NormalizedRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)))
        XCTAssertEqual(manager.document.items.count, 2)

        manager.clearAllItems()
        XCTAssertEqual(manager.document.items.count, 0)
        XCTAssertTrue(manager.canUndo)

        // Undo clear
        manager.undo()
        XCTAssertEqual(manager.document.items.count, 2)
    }
}
