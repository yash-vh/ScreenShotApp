import Foundation
import Combine

/// Manages undo and redo document state transitions with snapshot history.
@MainActor
public final class UndoRedoManager: ObservableObject {
    @Published public private(set) var document: AnnotationDocument

    private var undoStack: [AnnotationDocument] = []
    private var redoStack: [AnnotationDocument] = []
    private let maxHistory = 50

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

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
    }

    public func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(document)
        document = previous
    }

    public func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(document)
        document = next
    }

    // MARK: - Document Mutations

    public func addItem(_ item: AnnotationItem) {
        recordSnapshot()
        document.items.append(item)
        document.modifiedAt = Date()
    }

    public func updateItem(_ item: AnnotationItem) {
        guard let index = document.items.firstIndex(where: { $0.id == item.id }) else { return }
        recordSnapshot()
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
}
