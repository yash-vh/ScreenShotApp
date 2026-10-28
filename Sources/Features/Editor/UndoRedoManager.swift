import Foundation
import Combine

/// Manages undo and redo document state transitions with snapshot history.
///
/// Continuous interactions (dragging, resizing, slider scrubbing) should either call
/// `beginInteractiveChange()` once and then mutate with `registerUndo: false`, or pass a
/// `coalescingKey` so that consecutive edits collapse into a single undo step.
@MainActor
public final class UndoRedoManager: ObservableObject {
    @Published public private(set) var document: AnnotationDocument
    @Published public private(set) var canUndo = false
    @Published public private(set) var canRedo = false

    private var undoStack: [AnnotationDocument] = []
    private var redoStack: [AnnotationDocument] = []
    private var lastCoalescingKey: String?
    private let maxHistory = 100

    public init(document: AnnotationDocument) {
        self.document = document
    }

    // MARK: - History Operations

    /// Records the current state onto the undo stack prior to a mutation
    public func recordSnapshot() {
        undoStack.append(document)
        if undoStack.count > maxHistory {
            undoStack.removeFirst()
        }
        redoStack.removeAll()
        lastCoalescingKey = nil
        refreshFlags()
    }

    /// Records a single undo step for a gesture that will apply many un-registered mutations
    public func beginInteractiveChange() {
        recordSnapshot()
    }

    /// Ends any active coalescing run so the next coalesced edit starts a new undo step
    public func breakCoalescing() {
        lastCoalescingKey = nil
    }

    public func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(document)
        document = previous
        lastCoalescingKey = nil
        refreshFlags()
    }

    public func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(document)
        document = next
        lastCoalescingKey = nil
        refreshFlags()
    }

    // MARK: - Document Mutations

    public func addItem(_ item: AnnotationItem) {
        recordSnapshot()
        document.items.append(item)
        document.modifiedAt = Date()
    }

    /// Replaces an item. No-op (and no undo step) when the item is unchanged.
    public func updateItem(_ item: AnnotationItem, registerUndo: Bool = true, coalescingKey: String? = nil) {
        guard let index = document.items.firstIndex(where: { $0.id == item.id }),
              document.items[index] != item else { return }
        registerIfNeeded(registerUndo: registerUndo, coalescingKey: coalescingKey)
        document.items[index] = item
        document.modifiedAt = Date()
    }

    public func removeItem(id: UUID) {
        guard let index = document.items.firstIndex(where: { $0.id == id }) else { return }
        recordSnapshot()
        document.items.remove(at: index)
        document.modifiedAt = Date()
    }

    public func clearAllItems() {
        guard !document.items.isEmpty else { return }
        recordSnapshot()
        document.items.removeAll()
        document.modifiedAt = Date()
    }

    /// Moves an item to the top (`toFront`) or bottom of the z-order
    public func reorderItem(id: UUID, toFront: Bool) {
        guard let index = document.items.firstIndex(where: { $0.id == id }) else { return }
        let target = toFront ? document.items.count - 1 : 0
        guard index != target else { return }
        recordSnapshot()
        let item = document.items.remove(at: index)
        document.items.insert(item, at: toFront ? document.items.count : 0)
        document.modifiedAt = Date()
    }

    /// Applies an arbitrary document-level mutation (e.g. styling). No-op when nothing changes.
    public func updateDocument(registerUndo: Bool = true, coalescingKey: String? = nil, _ mutate: (inout AnnotationDocument) -> Void) {
        var copy = document
        mutate(&copy)
        guard copy != document else { return }
        registerIfNeeded(registerUndo: registerUndo, coalescingKey: coalescingKey)
        copy.modifiedAt = Date()
        document = copy
    }

    // MARK: - Helpers

    private func registerIfNeeded(registerUndo: Bool, coalescingKey: String?) {
        guard registerUndo else { return }
        if let key = coalescingKey, key == lastCoalescingKey, !undoStack.isEmpty {
            return
        }
        recordSnapshot()
        lastCoalescingKey = coalescingKey
    }

    private func refreshFlags() {
        if canUndo != !undoStack.isEmpty { canUndo = !undoStack.isEmpty }
        if canRedo != !redoStack.isEmpty { canRedo = !redoStack.isEmpty }
    }
}
