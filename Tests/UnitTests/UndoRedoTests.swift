import XCTest
@testable import ScreenMint

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

    func testNoOpUpdateDoesNotCreateUndoStep() {
        let item = AnnotationItem(type: .rectangle, bounds: NormalizedRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2))
        let manager = UndoRedoManager(document: AnnotationDocument(assetId: UUID(), items: [item]))
        manager.updateItem(item)
        XCTAssertFalse(manager.canUndo, "Re-applying identical values (e.g. selecting an item) must not pollute history")
    }

    func testInteractiveDragIsSingleUndoStep() {
        let item = AnnotationItem(type: .rectangle, bounds: NormalizedRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2))
        let manager = UndoRedoManager(document: AnnotationDocument(assetId: UUID(), items: [item]))

        manager.beginInteractiveChange()
        for step in 1...30 {
            var moved = item
            moved.bounds = NormalizedRect(x: 0.1 + Double(step) * 0.01, y: 0.1, width: 0.2, height: 0.2)
            manager.updateItem(moved, registerUndo: false)
        }
        XCTAssertEqual(manager.document.items[0].bounds.origin.x, 0.4, accuracy: 0.0001)

        manager.undo()
        XCTAssertEqual(manager.document.items[0].bounds.origin.x, 0.1, accuracy: 0.0001, "One undo reverts the whole drag")
        XCTAssertFalse(manager.canUndo)
        manager.redo()
        XCTAssertEqual(manager.document.items[0].bounds.origin.x, 0.4, accuracy: 0.0001)
    }

    func testCoalescedStyleChangesCollapseUntilBroken() {
        let item = AnnotationItem(type: .blur, bounds: NormalizedRect(x: 0, y: 0, width: 0.5, height: 0.5), blurRadius: 10)
        let manager = UndoRedoManager(document: AnnotationDocument(assetId: UUID(), items: [item]))

        for radius in stride(from: 12.0, through: 30.0, by: 2.0) {
            var updated = manager.document.items[0]
            updated.blurRadius = radius
            manager.updateItem(updated, coalescingKey: "blur")
        }
        manager.breakCoalescing()
        var again = manager.document.items[0]
        again.blurRadius = 50
        manager.updateItem(again, coalescingKey: "blur")

        manager.undo()
        XCTAssertEqual(manager.document.items[0].blurRadius, 30)
        manager.undo()
        XCTAssertEqual(manager.document.items[0].blurRadius, 10)
        XCTAssertFalse(manager.canUndo)
    }

    func testReorderAndDocumentStyling() {
        let a = AnnotationItem(type: .rectangle, bounds: NormalizedRect(x: 0, y: 0, width: 0.1, height: 0.1))
        let b = AnnotationItem(type: .ellipse, bounds: NormalizedRect(x: 0.5, y: 0.5, width: 0.1, height: 0.1))
        let manager = UndoRedoManager(document: AnnotationDocument(assetId: UUID(), items: [a, b]))

        manager.reorderItem(id: a.id, toFront: true)
        XCTAssertEqual(manager.document.items.map(\.id), [b.id, a.id])

        manager.updateDocument { $0.padding = 40 }
        XCTAssertTrue(manager.document.hasStyling)
        manager.undo()
        XCTAssertFalse(manager.document.hasStyling)
        manager.undo()
        XCTAssertEqual(manager.document.items.map(\.id), [a.id, b.id])
    }
}
