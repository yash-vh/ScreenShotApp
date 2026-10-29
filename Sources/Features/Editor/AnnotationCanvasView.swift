import AppKit
import CoreGraphics
import Combine

/// Interactive AppKit canvas view for drawing, in-place text editing, selecting, moving, resizing,
/// and manipulating annotations over a base image.
public final class AnnotationCanvasView: NSView, NSTextFieldDelegate, NSMenuItemValidation {
    /// How the canvas lays out the screenshot
    public enum Presentation {
        /// Editor window: centered card on a dark studio backdrop, fit-to-window
        case editor
        /// Capture overlay: the image fills the view 1:1 in points (inset only by styling padding)
        case embedded
    }

    /// Phases of a mouse gesture on empty canvas space with the select tool (embedded hosts use it to move the selection)
    public enum BackgroundDragPhase {
        case began, changed, ended
    }

    public override var isFlipped: Bool { true }
    public let presentation: Presentation
    public override var acceptsFirstResponder: Bool { true }

    public let undoRedoManager: UndoRedoManager
    public let state: EditorState

    public var baseCGImage: CGImage? {
        didSet {
            rebuildPreviewBase()
            textLineTask?.cancel()
            textLineTask = nil
            textLineBoxes = nil
            if state.tool == .highlight { loadTextLinesIfNeeded() }
            needsDisplay = true
        }
    }

    public var currentTool: EditorTool {
        get { state.tool }
        set { if state.tool != newValue { state.tool = newValue } }
    }

    // MARK: - Selection & Interaction State

    public private(set) var selectedItemId: UUID? {
        didSet {
            guard oldValue != selectedItemId else { return }
            if state.hasSelection != (selectedItemId != nil) {
                state.hasSelection = selectedItemId != nil
            }
            syncStateFromSelection()
            needsDisplay = true
        }
    }

    private enum Handle: CaseIterable {
        case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left
    }

    private enum Interaction {
        case drawing(start: CGPoint, current: CGPoint)
        case moving(original: AnnotationItem, mouseStart: CGPoint)
        case resizing(original: AnnotationItem, handle: Handle, grabOffset: CGVector)
        case arrowEndpoint(original: AnnotationItem, index: Int)
    }

    private var interaction: Interaction?
    private var interactionRegisteredUndo = false
    private var freehandPoints: [NormalizedPoint] = []

    /// Suppresses applying toolbar style changes back onto the selection while syncing from it
    private var isSyncingFromSelection = false

    // Inline Text Editing
    private var activeInlineTextField: NSTextField?
    private var activeEditingTextItemId: UUID?
    private var inlineTextOrigin: CGPoint = .zero
    private var inlineTextColor: AnnotationColor = .red
    private var inlineTextFontSize: Double = 22

    // Live redaction preview (computed on a downscaled copy of the base image)
    private var previewBaseImage: CGImage?
    private var previewImage: CGImage?
    private var previewRedactionItems: [AnnotationItem] = []

    // Recognized text lines the highlighter snaps to (loaded when the highlighter is picked)
    private var textLineBoxes: [NormalizedRect]?
    private var textLineTask: Task<Void, Never>?
    private var autoRedactTask: Task<Void, Never>?

    // Floating Toast Notification
    private var toastMessage: String?
    private var toastTimer: Timer?

    // Action Callbacks
    public var onCopyRequested: (() -> Void)?
    public var onSaveRequested: (() -> Void)?
    public var onCloseRequested: (() -> Void)?
    /// Return/Enter pressed with no text annotation selected
    public var onConfirmRequested: (() -> Void)?
    /// Receives select-tool drags that start on empty space; return false from `.began` to decline
    public var onBackgroundDrag: ((BackgroundDragPhase, NSEvent) -> Bool)?
    private var isForwardingBackgroundDrag = false

    /// Whether an inline text field is currently being edited
    public var isEditingText: Bool { activeInlineTextField != nil }

    private var cancellables = Set<AnyCancellable>()

    private static let backdropColor = NSColor(calibratedRed: 0.11, green: 0.11, blue: 0.13, alpha: 1.0)
    private static let selectionColor = NSColor.systemBlue
    private static let handleSize: CGFloat = 8
    private static let previewMaxDimension: CGFloat = 2400

    // MARK: - Init

    public init(frame: NSRect, undoRedoManager: UndoRedoManager, state: EditorState, baseImage: CGImage? = nil, presentation: Presentation = .editor) {
        self.undoRedoManager = undoRedoManager
        self.state = state
        self.baseCGImage = baseImage
        self.presentation = presentation
        super.init(frame: frame)

        rebuildPreviewBase()

        undoRedoManager.$document
            .sink { [weak self] doc in
                self?.documentDidChange(doc)
            }
            .store(in: &cancellables)

        // @Published emits before the stored value changes, so every sink works from the emitted value
        state.$tool
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] tool in
                self?.toolDidChange(to: tool)
            }
            .store(in: &cancellables)

        state.$color.dropFirst().sink { [weak self] color in
            self?.updateInlineTextFieldStyle(color: color)
            self?.applyToSelection(key: "color", where: { $0.type != .blur && $0.type != .pixelation }) { $0.strokeColor = color }
        }.store(in: &cancellables)

        state.$strokeWidth.dropFirst().sink { [weak self] width in
            self?.applyToSelection(key: "width", where: { Self.strokedTypes.contains($0.type) }) { $0.strokeWidth = width }
        }.store(in: &cancellables)

        state.$fontSize.dropFirst().sink { [weak self] size in
            self?.updateInlineTextFieldStyle(fontSize: size)
            self?.applyFontSize(size)
        }.store(in: &cancellables)

        state.$blurRadius.dropFirst().sink { [weak self] radius in
            self?.applyToSelection(key: "blur", where: { $0.type == .blur || $0.type == .pixelation }) { $0.blurRadius = radius }
        }.store(in: &cancellables)

        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.activeInKeyWindow, .mouseMoved, .cursorUpdate, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    public override func viewDidEndLiveResize() {
        super.viewDidEndLiveResize()
        repositionInlineTextField()
    }

    public override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        repositionInlineTextField()
    }

    // MARK: - Layout

    private var document: AnnotationDocument { undoRedoManager.document }

    private var pixelsPerPoint: CGFloat { CGFloat(max(document.pixelsPerPoint, 0.1)) }

    /// Rect enclosing the styled card (image + padding) in view coordinates
    public var styledRect: CGRect {
        guard presentation == .editor else { return bounds }
        guard let base = baseCGImage else { return bounds }
        let margin: CGFloat = 24.0
        let available = bounds.insetBy(dx: margin, dy: margin)
        let pad = CGFloat(document.padding) * pixelsPerPoint
        let contentW = CGFloat(base.width) + pad * 2
        let contentH = CGFloat(base.height) + pad * 2
        guard contentW > 0, contentH > 0, available.width > 0, available.height > 0 else { return bounds }

        let scale = min(available.width / contentW, available.height / contentH, 1.0 / pixelsPerPoint)
        let w = floor(contentW * scale)
        let h = floor(contentH * scale)
        return CGRect(x: floor(available.midX - w / 2), y: floor(available.midY - h / 2), width: w, height: h)
    }

    /// Aspect-fit rectangle of the base screenshot inside the styled card
    public var imageRect: CGRect {
        if presentation == .embedded {
            // 1 view point == 1 annotation point; padding (in points) surrounds the image
            let pad = CGFloat(document.padding)
            return bounds.insetBy(dx: pad, dy: pad)
        }
        guard let base = baseCGImage, base.width > 0 else { return bounds }
        let outer = styledRect
        let pad = CGFloat(document.padding) * pixelsPerPoint
        let scale = outer.width / (CGFloat(base.width) + pad * 2)
        return outer.insetBy(dx: pad * scale, dy: pad * scale)
    }

    /// View points per annotation point at the current zoom level
    public var displayScale: CGFloat {
        guard let base = baseCGImage, base.width > 0 else { return 1 }
        return imageRect.width / (CGFloat(base.width) / pixelsPerPoint)
    }

    private var renderer: AnnotationRenderer {
        AnnotationRenderer(imageRect: imageRect, scale: displayScale)
    }

    // MARK: - Toast Message

    public func showToast(_ message: String) {
        toastTimer?.invalidate()
        toastMessage = message
        needsDisplay = true

        toastTimer = Timer.scheduledTimer(withTimeInterval: 1.8, repeats: false) { [weak self] _ in
            self?.toastMessage = nil
            self?.needsDisplay = true
        }
    }

    // MARK: - State Observation

    private func documentDidChange(_ doc: AnnotationDocument) {
        if let id = selectedItemId, !doc.items.contains(where: { $0.id == id }) {
            selectedItemId = nil
        }
        updatePreviewIfNeeded(items: doc.items)
        needsDisplay = true
    }

    private func toolDidChange(to tool: EditorTool) {
        commitInlineTextEditor()
        if tool == .highlight { loadTextLinesIfNeeded() }
        if tool != .select {
            selectedItemId = nil
        }
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let window = self.window else { return }
            self.updateCursor(at: self.convert(window.mouseLocationOutsideOfEventStream, from: nil))
        }
        needsDisplay = true
    }

    private static let strokedTypes: Set<AnnotationType> = [.arrow, .rectangle, .ellipse, .freehand]

    private func syncStateFromSelection() {
        guard let item = selectedItem else { return }
        isSyncingFromSelection = true
        defer { isSyncingFromSelection = false }

        if item.type != .blur && item.type != .pixelation && state.color != item.strokeColor {
            state.color = item.strokeColor
        }
        if Self.strokedTypes.contains(item.type) && state.strokeWidth != item.strokeWidth {
            state.strokeWidth = item.strokeWidth
        }
        if item.type == .text || item.type == .step, let size = item.fontSize, state.fontSize != size {
            state.fontSize = size
        }
        if let radius = item.blurRadius, item.type == .blur || item.type == .pixelation, state.blurRadius != radius {
            state.blurRadius = radius
        }
    }

    /// Applies a toolbar style change to the selected annotation, coalescing slider scrubs into one undo step
    private func applyToSelection(key: String, where applies: (AnnotationItem) -> Bool, _ mutate: (inout AnnotationItem) -> Void) {
        guard !isSyncingFromSelection, activeEditingTextItemId == nil, let item = selectedItem, applies(item) else { return }
        var updated = item
        mutate(&updated)
        undoRedoManager.updateItem(updated, coalescingKey: "\(key)-\(item.id)")
    }

    private func applyFontSize(_ size: Double) {
        if selectedItem?.type == .step {
            applyToSelection(key: "font", where: { $0.type == .step }) { updated in
                let center = renderer.point(for: NormalizedPoint(
                    x: updated.bounds.origin.x + updated.bounds.width / 2,
                    y: updated.bounds.origin.y + updated.bounds.height / 2
                ))
                updated.fontSize = size
                updated.bounds = stepBounds(centeredAt: center, size: size)
            }
            return
        }
        let origin = selectedItem.map { renderer.point(for: $0.bounds.origin) } ?? .zero
        applyToSelection(key: "font", where: { $0.type == .text }) { updated in
            updated.fontSize = size
            if let text = updated.textContent {
                updated.bounds = textBounds(for: text, origin: origin, fontSize: size)
            }
        }
    }

    private var selectedItem: AnnotationItem? {
        guard let id = selectedItemId else { return nil }
        return document.items.first { $0.id == id }
    }

    // MARK: - Keyboard Handling

    public override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard event.window == nil || event.window === window, flags.contains(.command) else {
            return super.performKeyEquivalent(with: event)
        }

        // While typing, route standard editing shortcuts to the field editor (works without an Edit menu)
        if let editor = activeInlineTextField?.currentEditor() as? NSTextView {
            let action: Selector?
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "a": action = #selector(NSText.selectAll(_:))
            case "c": action = #selector(NSText.copy(_:))
            case "v": action = #selector(NSText.paste(_:))
            case "x": action = #selector(NSText.cut(_:))
            case "z":
                if flags.contains(.shift) { editor.undoManager?.redo() } else { editor.undoManager?.undo() }
                return true
            default: action = nil
            }
            if let action = action, NSApp.sendAction(action, to: editor, from: self) {
                return true
            }
            return super.performKeyEquivalent(with: event)
        }

        return handleCommandKey(event, flags: flags) || super.performKeyEquivalent(with: event)
    }

    private func handleCommandKey(_ event: NSEvent, flags: NSEvent.ModifierFlags) -> Bool {
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        let isShift = flags.contains(.shift)

        switch (event.keyCode, key) {
        case (_, "t") where isShift:
            state.isShowingRecognition.toggle()
        case (_, "z") where isShift, (_, "y"):
            redo(nil)
        case (_, "z"):
            undo(nil)
        case (_, "c"):
            copy(nil)
        case (_, "s"):
            saveDocument(nil)
        case (_, "d"):
            duplicate(nil)
        case (_, "w"):
            onCloseRequested?()
        case (_, "]"):
            bringToFront(nil)
        case (_, "["):
            sendToBack(nil)
        case (51, _), (117, _):
            delete(nil)
        default:
            return false
        }
        return true
    }

    public override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) {
            if !handleCommandKey(event, flags: flags) { super.keyDown(with: event) }
            return
        }

        switch event.keyCode {
        case 51, 117: // Delete / Forward Delete
            if selectedItemId != nil { delete(nil) } else { NSSound.beep() }
            return
        case 53: // Escape
            cancelOperation(nil)
            return
        case 36, 76: // Return / Enter: edit selected text, otherwise confirm (e.g. copy in the capture overlay)
            if let item = selectedItem, item.type == .text {
                startInlineTextEditor(for: item)
            } else if let confirm = onConfirmRequested {
                confirm()
            } else {
                super.keyDown(with: event)
            }
            return
        case 123, 124, 125, 126: // Arrow keys nudge the selection
            nudgeSelection(keyCode: event.keyCode, large: flags.contains(.shift))
            return
        default:
            break
        }

        guard flags.isDisjoint(with: [.control, .option]),
              let key = event.charactersIgnoringModifiers?.lowercased(),
              let tool = Self.toolShortcuts[key] else {
            super.keyDown(with: event)
            return
        }
        currentTool = tool
    }

    public static let toolShortcuts: [String: EditorTool] = [
        "v": .select, "a": .arrow, "r": .rectangle, "o": .ellipse, "p": .freehand,
        "h": .highlight, "t": .text, "n": .step, "b": .blur, "x": .pixelate
    ]

    public override func cancelOperation(_ sender: Any?) {
        if interaction != nil {
            cancelInteraction()
        } else if selectedItemId != nil {
            selectedItemId = nil
        } else {
            onCloseRequested?()
        }
    }

    private func nudgeSelection(keyCode: UInt16, large: Bool) {
        guard let item = selectedItem else { return }
        let iRect = imageRect
        guard iRect.width > 0, iRect.height > 0 else { return }
        let step: CGFloat = large ? 10 : 1
        var dx: CGFloat = 0, dy: CGFloat = 0
        switch keyCode {
        case 123: dx = -step
        case 124: dx = step
        case 125: dy = step
        default: dy = -step
        }
        let moved = Self.translated(item, dx: dx / iRect.width, dy: dy / iRect.height)
        undoRedoManager.updateItem(moved, coalescingKey: "nudge-\(item.id)")
    }

    // MARK: - Responder Actions (Edit menu & shortcuts)

    @objc public func undo(_ sender: Any?) {
        commitInlineTextEditor()
        cancelInteraction()
        undoRedoManager.undo()
    }

    @objc public func redo(_ sender: Any?) {
        commitInlineTextEditor()
        cancelInteraction()
        undoRedoManager.redo()
    }

    @objc public func copy(_ sender: Any?) {
        commitInlineTextEditor()
        onCopyRequested?()
    }

    @objc public func saveDocument(_ sender: Any?) {
        commitInlineTextEditor()
        onSaveRequested?()
    }

    @objc public func delete(_ sender: Any?) {
        guard let id = selectedItemId else { return }
        undoRedoManager.removeItem(id: id)
        selectedItemId = nil
    }

    @objc public func duplicate(_ sender: Any?) {
        guard let item = selectedItem else { return }
        let iRect = imageRect
        let offset: CGFloat = 16
        var copy = Self.translated(item, dx: offset / max(iRect.width, 1), dy: offset / max(iRect.height, 1))
        copy = AnnotationItem(
            type: copy.type, bounds: copy.bounds, strokeColor: copy.strokeColor, fillColor: copy.fillColor,
            strokeWidth: copy.strokeWidth, textContent: copy.textContent, fontSize: copy.fontSize,
            points: copy.points, blurRadius: copy.blurRadius
        )
        undoRedoManager.addItem(copy)
        selectedItemId = copy.id
    }

    @objc public func bringToFront(_ sender: Any?) {
        guard let id = selectedItemId else { return }
        undoRedoManager.reorderItem(id: id, toFront: true)
    }

    @objc public func sendToBack(_ sender: Any?) {
        guard let id = selectedItemId else { return }
        undoRedoManager.reorderItem(id: id, toFront: false)
    }

    @objc public func editText(_ sender: Any?) {
        guard let item = selectedItem, item.type == .text else { return }
        startInlineTextEditor(for: item)
    }

    public func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(undo(_:)): return undoRedoManager.canUndo
        case #selector(redo(_:)): return undoRedoManager.canRedo
        case #selector(delete(_:)), #selector(duplicate(_:)), #selector(bringToFront(_:)), #selector(sendToBack(_:)):
            return selectedItemId != nil
        case #selector(editText(_:)): return selectedItem?.type == .text
        default: return true
        }
    }

    public override func menu(for event: NSEvent) -> NSMenu? {
        let loc = convert(event.locationInWindow, from: nil)
        guard let hit = findItem(at: loc, forSelectTool: true) else { return nil }
        commitInlineTextEditor()
        selectedItemId = hit.id

        let menu = NSMenu()
        if hit.type == .text {
            menu.addItem(withTitle: "Edit Text", action: #selector(editText(_:)), keyEquivalent: "\r")
            menu.addItem(.separator())
        }
        menu.addItem(withTitle: "Duplicate", action: #selector(duplicate(_:)), keyEquivalent: "d")
        menu.addItem(withTitle: "Bring to Front", action: #selector(bringToFront(_:)), keyEquivalent: "]")
        menu.addItem(withTitle: "Send to Back", action: #selector(sendToBack(_:)), keyEquivalent: "[")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Delete", action: #selector(delete(_:)), keyEquivalent: "")
        menu.items.forEach { $0.target = self }
        return menu
    }

    // MARK: - Live Redaction Preview

    private func rebuildPreviewBase() {
        guard let base = baseCGImage else {
            previewBaseImage = nil
            previewImage = nil
            return
        }
        let longEdge = CGFloat(max(base.width, base.height))
        if longEdge > Self.previewMaxDimension, let scaled = Self.downscale(base, factor: Self.previewMaxDimension / longEdge) {
            previewBaseImage = scaled
        } else {
            previewBaseImage = base
        }
        previewRedactionItems = []
        previewImage = nil
        updatePreviewIfNeeded(items: document.items, force: true)
    }

    private func updatePreviewIfNeeded(items: [AnnotationItem], force: Bool = false) {
        let redactions = items.filter { $0.type == .blur || $0.type == .pixelation }
        guard force || redactions != previewRedactionItems else { return }
        previewRedactionItems = redactions

        guard let preview = previewBaseImage, let base = baseCGImage, !redactions.isEmpty else {
            previewImage = nil
            return
        }

        // Radii are authored in full-resolution pixels; scale them to the preview copy
        let factor = Double(preview.width) / Double(base.width)
        let scaled = redactions.map { item -> AnnotationItem in
            var copy = item
            copy.blurRadius = (item.blurRadius ?? 20.0) * factor
            return copy
        }
        previewImage = ExportCompositor.applyRedactions(to: preview, items: scaled)
    }

    private static func downscale(_ image: CGImage, factor: CGFloat) -> CGImage? {
        let w = max(Int(CGFloat(image.width) * factor), 1)
        let h = max(Int(CGFloat(image.height) * factor), 1)
        guard let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }

    // MARK: - Mouse Events

    public override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        undoRedoManager.breakCoalescing()
        let loc = convert(event.locationInWindow, from: nil)

        // Clicking anywhere outside an active inline text editor commits it
        if activeInlineTextField != nil {
            commitInlineTextEditor()
            return
        }

        // Double-click on text edits it in place
        if event.clickCount == 2, let hit = findItem(at: loc, forSelectTool: true), hit.type == .text {
            selectedItemId = hit.id
            startInlineTextEditor(for: hit)
            return
        }

        // Handles of the current selection take priority (resize / arrow endpoints)
        if let item = selectedItem {
            if item.type == .arrow, let index = arrowEndpointIndex(of: item, at: loc) {
                beginInteraction(.arrowEndpoint(original: item, index: index))
                return
            }
            if let handle = handle(of: item, at: loc) {
                // Remember where inside the handle the pointer grabbed so the edge doesn't jump
                let edge = edgePoint(of: renderer.rect(for: item.bounds), handle: handle)
                beginInteraction(.resizing(original: item, handle: handle, grabOffset: CGVector(dx: loc.x - edge.x, dy: loc.y - edge.y)))
                return
            }
        }

        // Select & move an existing annotation
        if let hit = findItem(at: loc, forSelectTool: currentTool == .select) {
            selectedItemId = hit.id
            beginInteraction(.moving(original: hit, mouseStart: loc))
            return
        }

        if currentTool == .select {
            selectedItemId = nil
            if let handler = onBackgroundDrag, handler(.began, event) {
                isForwardingBackgroundDrag = true
            }
            return
        }

        guard imageRect.contains(loc) else {
            selectedItemId = nil
            return
        }

        if currentTool == .text {
            selectedItemId = nil
            startNewInlineTextEditor(at: loc)
            return
        }

        if currentTool == .step {
            placeStep(at: loc)
            return
        }

        // Start drawing a new annotation
        selectedItemId = nil
        if currentTool == .freehand {
            freehandPoints = [normalize(point: loc)]
        }
        beginInteraction(.drawing(start: loc, current: loc))
    }

    public override func mouseDragged(with event: NSEvent) {
        if isForwardingBackgroundDrag {
            _ = onBackgroundDrag?(.changed, event)
            return
        }
        guard let interaction = interaction else { return }
        let loc = convert(event.locationInWindow, from: nil)
        let shift = event.modifierFlags.contains(.shift)
        let iRect = imageRect
        guard iRect.width > 0, iRect.height > 0 else { return }

        switch interaction {
        case .drawing(let start, _):
            let clamped = clampToImage(loc)
            let current = shift ? constrained(from: start, to: clamped, tool: currentTool) : clamped
            self.interaction = .drawing(start: start, current: current)
            if currentTool == .freehand {
                freehandPoints.append(normalize(point: clamped))
            }

        case .moving(let original, let mouseStart):
            var dx = (loc.x - mouseStart.x) / iRect.width
            var dy = (loc.y - mouseStart.y) / iRect.height
            if shift {
                if abs(dx) > abs(dy) { dy = 0 } else { dx = 0 }
            }
            applyInteractive(Self.translated(original, dx: dx, dy: dy))

        case .resizing(let original, let handle, let grabOffset):
            let target = clampToImage(CGPoint(x: loc.x - grabOffset.dx, y: loc.y - grabOffset.dy))
            applyInteractive(resized(original, handle: handle, to: target, keepAspect: shift))

        case .arrowEndpoint(let original, let index):
            guard var pts = original.points, pts.count >= 2 else { return }
            let anchor = renderer.point(for: pts[1 - index])
            let target = shift ? constrained(from: anchor, to: clampToImage(loc), tool: .arrow) : clampToImage(loc)
            pts[index] = normalize(point: target)
            var updated = original
            updated.points = pts
            updated.bounds = Self.boundingRect(of: pts)
            applyInteractive(updated)
        }
        needsDisplay = true
    }

    public override func mouseUp(with event: NSEvent) {
        if isForwardingBackgroundDrag {
            isForwardingBackgroundDrag = false
            _ = onBackgroundDrag?(.ended, event)
            return
        }
        guard let interaction = interaction else { return }
        self.interaction = nil
        interactionRegisteredUndo = false

        if case .drawing(let start, let current) = interaction {
            commitDrawing(from: start, to: current)
        }
        freehandPoints.removeAll()
        updateCursor(at: convert(event.locationInWindow, from: nil))
        needsDisplay = true
    }

    public override func mouseMoved(with event: NSEvent) {
        updateCursor(at: convert(event.locationInWindow, from: nil))
    }

    public override func cursorUpdate(with event: NSEvent) {
        updateCursor(at: convert(event.locationInWindow, from: nil))
    }

    private func beginInteraction(_ newInteraction: Interaction) {
        interaction = newInteraction
        interactionRegisteredUndo = false
        needsDisplay = true
    }

    /// Applies a live gesture mutation, registering exactly one undo step on the first real change
    private func applyInteractive(_ item: AnnotationItem) {
        guard let current = document.items.first(where: { $0.id == item.id }), current != item else { return }
        if !interactionRegisteredUndo {
            undoRedoManager.beginInteractiveChange()
            interactionRegisteredUndo = true
        }
        undoRedoManager.updateItem(item, registerUndo: false)
    }

    private func cancelInteraction() {
        guard let active = interaction else { return }
        interaction = nil
        freehandPoints.removeAll()
        switch active {
        case .moving(let original, _), .resizing(let original, _, _), .arrowEndpoint(let original, _):
            if interactionRegisteredUndo {
                undoRedoManager.updateItem(original, registerUndo: false)
            }
        case .drawing:
            break
        }
        interactionRegisteredUndo = false
        needsDisplay = true
    }

    // MARK: - Geometry Helpers

    private func clampToImage(_ p: CGPoint) -> CGPoint {
        let r = imageRect
        return CGPoint(x: min(max(p.x, r.minX), r.maxX), y: min(max(p.y, r.minY), r.maxY))
    }

    /// Shift-constrains a drag: squares/circles for shapes, 45° steps for arrows
    private func constrained(from start: CGPoint, to end: CGPoint, tool: EditorTool) -> CGPoint {
        let dx = end.x - start.x
        let dy = end.y - start.y
        if tool == .arrow {
            let angle = (atan2(dy, dx) / (.pi / 4)).rounded() * (.pi / 4)
            let length = hypot(dx, dy)
            return clampToImage(CGPoint(x: start.x + cos(angle) * length, y: start.y + sin(angle) * length))
        }
        guard tool != .freehand else { return end }
        let side = max(abs(dx), abs(dy))
        return clampToImage(CGPoint(x: start.x + (dx < 0 ? -side : side), y: start.y + (dy < 0 ? -side : side)))
    }

    /// Translates an item by a normalized delta, clamped so the whole item stays inside the image
    static func translated(_ item: AnnotationItem, dx: Double, dy: Double) -> AnnotationItem {
        let b = item.bounds
        let clampedDX = min(max(dx, -b.origin.x), 1.0 - (b.origin.x + b.width))
        let clampedDY = min(max(dy, -b.origin.y), 1.0 - (b.origin.y + b.height))
        var moved = item
        moved.bounds = NormalizedRect(x: b.origin.x + clampedDX, y: b.origin.y + clampedDY, width: b.width, height: b.height)
        moved.points = item.points?.map { NormalizedPoint(x: $0.x + clampedDX, y: $0.y + clampedDY) }
        return moved
    }

    static func boundingRect(of points: [NormalizedPoint]) -> NormalizedRect {
        guard let first = points.first else { return NormalizedRect(x: 0, y: 0, width: 0, height: 0) }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for p in points.dropFirst() {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
        return NormalizedRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private func resized(_ original: AnnotationItem, handle: Handle, to loc: CGPoint, keepAspect: Bool) -> AnnotationItem {
        let old = renderer.rect(for: original.bounds)
        var minX = old.minX, maxX = old.maxX, minY = old.minY, maxY = old.maxY

        switch handle {
        case .topLeft: minX = loc.x; minY = loc.y
        case .top: minY = loc.y
        case .topRight: maxX = loc.x; minY = loc.y
        case .right: maxX = loc.x
        case .bottomRight: maxX = loc.x; maxY = loc.y
        case .bottom: maxY = loc.y
        case .bottomLeft: minX = loc.x; maxY = loc.y
        case .left: minX = loc.x
        }

        var newRect = CGRect(x: min(minX, maxX), y: min(minY, maxY), width: abs(maxX - minX), height: abs(maxY - minY))
        if keepAspect, old.width > 0, old.height > 0, [.topLeft, .topRight, .bottomLeft, .bottomRight].contains(handle) {
            let ratio = old.width / old.height
            if newRect.width / max(newRect.height, 0.001) > ratio {
                newRect.size.width = newRect.height * ratio
            } else {
                newRect.size.height = newRect.width / ratio
            }
            if handle == .topLeft || handle == .bottomLeft { newRect.origin.x = old.maxX - newRect.width }
            if handle == .topLeft || handle == .topRight { newRect.origin.y = old.maxY - newRect.height }
        }

        let normOrigin = normalize(point: newRect.origin)
        let normMax = normalize(point: CGPoint(x: newRect.maxX, y: newRect.maxY))
        let newBounds = NormalizedRect(x: normOrigin.x, y: normOrigin.y, width: normMax.x - normOrigin.x, height: normMax.y - normOrigin.y)

        var updated = original
        updated.bounds = newBounds

        // Freehand strokes scale with their bounding box
        if let pts = original.points, original.type == .freehand {
            let ob = original.bounds
            updated.points = pts.map { p in
                let fx = ob.width > 0 ? (p.x - ob.origin.x) / ob.width : 0
                let fy = ob.height > 0 ? (p.y - ob.origin.y) / ob.height : 0
                return NormalizedPoint(x: newBounds.origin.x + fx * newBounds.width, y: newBounds.origin.y + fy * newBounds.height)
            }
        }
        return updated
    }

    // MARK: - Hit Testing

    /// Finds the top-most annotation under `point`. Outlined shapes only hit near their stroke
    /// unless `forSelectTool` is set, so drawing tools can still start new shapes inside them.
    private func findItem(at point: CGPoint, forSelectTool: Bool) -> AnnotationItem? {
        let r = renderer
        for item in document.items.reversed() {
            let rect = r.rect(for: item.bounds)
            let tolerance = max(CGFloat(item.strokeWidth) * r.scale / 2, 0) + 6

            switch item.type {
            case .arrow:
                guard let pts = item.points, pts.count >= 2 else { continue }
                if Self.distance(from: point, toSegment: r.point(for: pts[0]), r.point(for: pts[1])) <= tolerance {
                    return item
                }
            case .freehand:
                guard let pts = item.points?.map({ r.point(for: $0) }), pts.count > 1 else { continue }
                for i in 1..<pts.count where Self.distance(from: point, toSegment: pts[i - 1], pts[i]) <= tolerance {
                    return item
                }
            case .rectangle:
                if forSelectTool ? rect.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
                    : (rect.insetBy(dx: -tolerance, dy: -tolerance).contains(point) && !rect.insetBy(dx: tolerance, dy: tolerance).contains(point)) {
                    return item
                }
            case .ellipse:
                if Self.ellipseHit(point, in: rect, tolerance: tolerance, filled: forSelectTool) {
                    return item
                }
            case .text, .highlight, .blur, .pixelation, .step:
                if rect.insetBy(dx: -4, dy: -4).contains(point) {
                    return item
                }
            }
        }
        return nil
    }

    private static func distance(from p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }

    private static func ellipseHit(_ p: CGPoint, in rect: CGRect, tolerance: CGFloat, filled: Bool) -> Bool {
        let rx = rect.width / 2, ry = rect.height / 2
        guard rx > 0, ry > 0 else { return false }
        let nx = (p.x - rect.midX), ny = (p.y - rect.midY)
        let outer = pow(nx / (rx + tolerance), 2) + pow(ny / (ry + tolerance), 2)
        guard outer <= 1 else { return false }
        if filled { return true }
        let innerRX = rx - tolerance, innerRY = ry - tolerance
        guard innerRX > 0, innerRY > 0 else { return true }
        return pow(nx / innerRX, 2) + pow(ny / innerRY, 2) >= 1
    }

    private func supportsResizeHandles(_ item: AnnotationItem) -> Bool {
        [.rectangle, .ellipse, .highlight, .blur, .pixelation, .freehand].contains(item.type)
    }

    private func handlePoints(for rect: CGRect) -> [(Handle, CGPoint)] {
        let r = rect.insetBy(dx: -4, dy: -4)
        return [
            (.topLeft, CGPoint(x: r.minX, y: r.minY)),
            (.top, CGPoint(x: r.midX, y: r.minY)),
            (.topRight, CGPoint(x: r.maxX, y: r.minY)),
            (.right, CGPoint(x: r.maxX, y: r.midY)),
            (.bottomRight, CGPoint(x: r.maxX, y: r.maxY)),
            (.bottom, CGPoint(x: r.midX, y: r.maxY)),
            (.bottomLeft, CGPoint(x: r.minX, y: r.maxY)),
            (.left, CGPoint(x: r.minX, y: r.midY))
        ]
    }

    /// The point on the item's (un-inset) bounds that a handle controls
    private func edgePoint(of rect: CGRect, handle: Handle) -> CGPoint {
        switch handle {
        case .topLeft: return CGPoint(x: rect.minX, y: rect.minY)
        case .top: return CGPoint(x: rect.midX, y: rect.minY)
        case .topRight: return CGPoint(x: rect.maxX, y: rect.minY)
        case .right: return CGPoint(x: rect.maxX, y: rect.midY)
        case .bottomRight: return CGPoint(x: rect.maxX, y: rect.maxY)
        case .bottom: return CGPoint(x: rect.midX, y: rect.maxY)
        case .bottomLeft: return CGPoint(x: rect.minX, y: rect.maxY)
        case .left: return CGPoint(x: rect.minX, y: rect.midY)
        }
    }

    private func handle(of item: AnnotationItem, at point: CGPoint) -> Handle? {
        guard supportsResizeHandles(item) else { return nil }
        let hitRadius = Self.handleSize
        for (handle, center) in handlePoints(for: renderer.rect(for: item.bounds))
        where abs(point.x - center.x) <= hitRadius && abs(point.y - center.y) <= hitRadius {
            return handle
        }
        return nil
    }

    private func arrowEndpointIndex(of item: AnnotationItem, at point: CGPoint) -> Int? {
        guard let pts = item.points, pts.count >= 2 else { return nil }
        for index in [1, 0] where hypot(point.x - renderer.point(for: pts[index]).x, point.y - renderer.point(for: pts[index]).y) <= Self.handleSize + 2 {
            return index
        }
        return nil
    }

    // MARK: - Cursor

    private func updateCursor(at loc: CGPoint) {
        guard interaction == nil else { return }
        if let item = selectedItem {
            if item.type == .arrow, arrowEndpointIndex(of: item, at: loc) != nil {
                NSCursor.crosshair.set(); return
            }
            if let handle = handle(of: item, at: loc) {
                switch handle {
                case .left, .right: NSCursor.resizeLeftRight.set()
                case .top, .bottom: NSCursor.resizeUpDown.set()
                default: NSCursor.crosshair.set()
                }
                return
            }
        }
        if findItem(at: loc, forSelectTool: currentTool == .select) != nil {
            NSCursor.openHand.set()
            return
        }
        switch currentTool {
        case .select: NSCursor.arrow.set()
        case .text: (imageRect.contains(loc) ? NSCursor.iBeam : NSCursor.arrow).set()
        default: (imageRect.contains(loc) ? NSCursor.crosshair : NSCursor.arrow).set()
        }
    }

    // MARK: - Annotation Commit

    private func commitDrawing(from start: CGPoint, to end: CGPoint) {
        let normStart = normalize(point: start)
        let normEnd = normalize(point: end)
        let minDragPoints: CGFloat = 4

        let itemType: AnnotationType
        var points: [NormalizedPoint]?
        var bounds = NormalizedRect(
            x: min(normStart.x, normEnd.x),
            y: min(normStart.y, normEnd.y),
            width: abs(normEnd.x - normStart.x),
            height: abs(normEnd.y - normStart.y)
        )

        switch currentTool {
        case .freehand:
            guard freehandPoints.count > 1 else { return }
            itemType = .freehand
            points = freehandPoints
            bounds = Self.boundingRect(of: freehandPoints)
        case .arrow:
            guard hypot(end.x - start.x, end.y - start.y) >= minDragPoints * 2 else { return }
            itemType = .arrow
            points = [normStart, normEnd]
        case .highlight where abs(end.x - start.x) >= minDragPoints:
            // Snap to the text lines under the stroke; a drag over no text falls back to a plain box
            let snapped = TextHighlightSnapper.snap(drag: bounds, lines: textLineBoxes ?? [])
            if !snapped.isEmpty {
                let items = snapped.map { AnnotationItem(type: .highlight, bounds: $0, strokeColor: state.color, strokeWidth: state.strokeWidth) }
                undoRedoManager.updateDocument { $0.items.append(contentsOf: items) }
                selectedItemId = items.count == 1 ? items[0].id : nil
                return
            }
            guard abs(end.y - start.y) >= minDragPoints else { return }
            itemType = .highlight
        default:
            guard abs(end.x - start.x) >= minDragPoints, abs(end.y - start.y) >= minDragPoints else { return }
            switch currentTool {
            case .rectangle: itemType = .rectangle
            case .ellipse: itemType = .ellipse
            case .highlight: itemType = .highlight
            case .blur: itemType = .blur
            case .pixelate: itemType = .pixelation
            default: return
            }
        }

        let isRedaction = itemType == .blur || itemType == .pixelation
        let item = AnnotationItem(
            type: itemType,
            bounds: bounds,
            strokeColor: isRedaction ? .black : state.color,
            strokeWidth: state.strokeWidth,
            points: points,
            blurRadius: isRedaction ? state.blurRadius : nil
        )
        undoRedoManager.addItem(item)
        selectedItemId = item.id
    }

    // MARK: - Step Markers

    /// Diameter of a step badge for the given size setting, in annotation points
    private static func stepDiameter(for size: Double) -> CGFloat { CGFloat(size) * 1.35 }

    private func stepBounds(centeredAt center: CGPoint, size: Double) -> NormalizedRect {
        let iRect = imageRect
        let d = Self.stepDiameter(for: size) * renderer.scale
        let x = min(max(center.x - d / 2, iRect.minX), iRect.maxX - d)
        let y = min(max(center.y - d / 2, iRect.minY), iRect.maxY - d)
        let origin = normalize(point: CGPoint(x: x, y: y))
        let corner = normalize(point: CGPoint(x: x + d, y: y + d))
        return NormalizedRect(x: origin.x, y: origin.y, width: corner.x - origin.x, height: corner.y - origin.y)
    }

    /// Drops the next numbered step (1, 2, 3…) centered on the click
    private func placeStep(at loc: CGPoint) {
        let item = AnnotationItem(
            type: .step,
            bounds: stepBounds(centeredAt: loc, size: state.fontSize),
            strokeColor: state.color,
            textContent: String(document.nextStepNumber),
            fontSize: state.fontSize
        )
        undoRedoManager.addItem(item)
        selectedItemId = item.id
    }

    // MARK: - Text-Aware Highlighting & Auto Redaction

    /// Recognizes text lines once per image so highlighter strokes can snap to them
    private func loadTextLinesIfNeeded() {
        guard textLineBoxes == nil, textLineTask == nil, let image = baseCGImage else { return }
        textLineTask = Task { @MainActor [weak self] in
            let result = try? await VisionService.shared.recognize(in: image, recognitionLevel: .fast)
            guard let self, !Task.isCancelled else { return }
            self.textLineBoxes = result?.textBlocks.map(\.boundingBox) ?? []
            self.textLineTask = nil
        }
    }

    /// Finds emails, phone numbers, card numbers, keys and similar text in the image and covers each with a redaction
    public func autoRedactSensitiveInfo() {
        guard autoRedactTask == nil, let image = baseCGImage else { return }
        commitInlineTextEditor()
        state.isAutoRedacting = true
        let style: AnnotationType = AppConfiguration.shared.captureSettings.defaultRedactionStyle == .pixelate ? .pixelation : .blur
        autoRedactTask = Task { @MainActor [weak self] in
            let regions = (try? await SensitiveInfoDetector.detectRegions(in: image)) ?? []
            guard let self else { return }
            self.autoRedactTask = nil
            self.state.isAutoRedacting = false
            guard !Task.isCancelled else { return }

            // Skip areas that are already covered by an earlier redaction
            let existing = self.document.items.filter { $0.type == .blur || $0.type == .pixelation }.map(\.bounds)
            let fresh = regions.filter { region in !existing.contains { $0 == region } }
            guard !fresh.isEmpty else {
                self.showToast("No sensitive info found")
                return
            }
            let items = fresh.map { AnnotationItem(type: style, bounds: $0, strokeColor: .black, blurRadius: self.state.blurRadius) }
            self.undoRedoManager.updateDocument { $0.items.append(contentsOf: items) }
            self.selectedItemId = nil
            self.showToast("Blurred \(items.count) sensitive item\(items.count == 1 ? "" : "s")")
        }
    }

    // MARK: - In-Place Text Editor

    private func startNewInlineTextEditor(at loc: CGPoint) {
        commitInlineTextEditor()
        presentInlineTextField(text: "", origin: loc, color: state.color, fontSize: state.fontSize)
        activeEditingTextItemId = nil
    }

    private func startInlineTextEditor(for item: AnnotationItem) {
        commitInlineTextEditor()
        selectedItemId = item.id
        presentInlineTextField(
            text: item.textContent ?? "",
            origin: renderer.point(for: item.bounds.origin),
            color: item.strokeColor,
            fontSize: item.fontSize ?? state.fontSize
        )
        activeEditingTextItemId = item.id
        needsDisplay = true
    }

    private func presentInlineTextField(text: String, origin: CGPoint, color: AnnotationColor, fontSize: Double) {
        inlineTextOrigin = CGPoint(
            x: (origin.x - imageRect.minX) / max(imageRect.width, 1),
            y: (origin.y - imageRect.minY) / max(imageRect.height, 1)
        )

        let tf = NSTextField(frame: .zero)
        tf.stringValue = text
        tf.placeholderString = "Type text…"
        tf.isBezeled = false
        tf.isBordered = false
        tf.drawsBackground = true
        tf.backgroundColor = NSColor.black.withAlphaComponent(0.35)
        tf.focusRingType = .none
        tf.wantsLayer = true
        tf.layer?.cornerRadius = 4
        tf.layer?.borderWidth = 1
        tf.layer?.borderColor = Self.selectionColor.cgColor
        tf.cell?.isScrollable = true
        tf.cell?.wraps = false
        tf.delegate = self

        addSubview(tf)
        activeInlineTextField = tf
        updateInlineTextFieldStyle(color: color, fontSize: fontSize)
        window?.makeFirstResponder(tf)
        tf.currentEditor()?.selectedRange = NSRange(location: (text as NSString).length, length: 0)
    }

    private func updateInlineTextFieldStyle(color: AnnotationColor? = nil, fontSize: Double? = nil) {
        guard let tf = activeInlineTextField else { return }
        let c = color ?? inlineTextColor
        let points = fontSize ?? inlineTextFontSize
        inlineTextColor = c
        inlineTextFontSize = points
        let size = CGFloat(points) * displayScale
        tf.font = AnnotationRenderer.font(ofSize: size)
        tf.textColor = NSColor(srgbRed: c.red, green: c.green, blue: c.blue, alpha: 1)
        repositionInlineTextField()
    }

    private func repositionInlineTextField() {
        guard let tf = activeInlineTextField else { return }
        let iRect = imageRect
        let origin = CGPoint(x: iRect.minX + inlineTextOrigin.x * iRect.width, y: iRect.minY + inlineTextOrigin.y * iRect.height)
        let font = tf.font ?? AnnotationRenderer.font(ofSize: 22)
        let content = tf.stringValue.isEmpty ? (tf.placeholderString ?? " ") : tf.stringValue
        let size = (content as NSString).size(withAttributes: [.font: font])
        let width = min(max(size.width + 24, 120), max(iRect.maxX - origin.x, 120))
        tf.frame = NSRect(x: origin.x, y: origin.y, width: width, height: ceil(font.ascender - font.descender + font.leading) + 6)
    }

    public func controlTextDidChange(_ obj: Notification) {
        repositionInlineTextField()
    }

    public func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.cancelOperation(_:)):
            dismissInlineTextEditor()
            return true
        case #selector(NSResponder.insertNewline(_:)):
            commitInlineTextEditor()
            return true
        default:
            return false
        }
    }

    public func controlTextDidEndEditing(_ obj: Notification) {
        commitInlineTextEditor()
    }

    private func textBounds(for text: String, origin: CGPoint, fontSize: Double) -> NormalizedRect {
        let iRect = imageRect
        let size = AnnotationRenderer.textSize(text, fontSize: CGFloat(fontSize) * displayScale)
        let normOrigin = normalize(point: origin)
        return NormalizedRect(
            x: normOrigin.x,
            y: normOrigin.y,
            width: min(size.width / max(iRect.width, 1), 1.0 - normOrigin.x),
            height: min(size.height / max(iRect.height, 1), 1.0 - normOrigin.y)
        )
    }

    private func commitInlineTextEditor() {
        guard let tf = activeInlineTextField else { return }
        // Detach first: removing the field ends editing, which re-enters this method via the delegate
        activeInlineTextField = nil
        let editingId = activeEditingTextItemId
        activeEditingTextItemId = nil
        let text = tf.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let origin = CGPoint(x: tf.frame.minX, y: tf.frame.minY)
        tf.delegate = nil
        tf.removeFromSuperview()
        window?.makeFirstResponder(self)

        if let id = editingId, let existing = document.items.first(where: { $0.id == id }) {
            if text.isEmpty {
                undoRedoManager.removeItem(id: id)
            } else {
                var updated = existing
                updated.textContent = text
                updated.strokeColor = inlineTextColor
                updated.fontSize = inlineTextFontSize
                updated.bounds = textBounds(for: text, origin: origin, fontSize: inlineTextFontSize)
                undoRedoManager.updateItem(updated)
            }
        } else if !text.isEmpty {
            let item = AnnotationItem(
                type: .text,
                bounds: textBounds(for: text, origin: origin, fontSize: inlineTextFontSize),
                strokeColor: inlineTextColor,
                textContent: text,
                fontSize: inlineTextFontSize
            )
            undoRedoManager.addItem(item)
            selectedItemId = item.id
        }
        needsDisplay = true
    }

    private func dismissInlineTextEditor() {
        guard let tf = activeInlineTextField else { return }
        activeInlineTextField = nil
        activeEditingTextItemId = nil
        tf.delegate = nil
        tf.removeFromSuperview()
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    // MARK: - Drawing

    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        if presentation == .editor {
            Self.backdropColor.setFill()
            dirtyRect.fill()
        }

        let iRect = imageRect
        guard iRect.width > 0, iRect.height > 0 else { return }

        drawStyledCard(in: context, imageRect: iRect)

        let r = renderer
        for item in document.items where item.id != activeEditingTextItemId {
            r.draw(item, in: context)
        }

        if case .drawing(let start, let current)? = interaction {
            drawInProgressItem(from: start, to: current, in: context)
        }

        if let item = selectedItem, activeInlineTextField == nil || activeEditingTextItemId != item.id {
            drawSelection(for: item, in: context)
        }

        if let toast = toastMessage {
            drawToastOverlay(toast, in: context)
        }
    }

    /// Draws backdrop, shadow, rounded clipping and the (live-redacted) screenshot
    private func drawStyledCard(in context: CGContext, imageRect iRect: CGRect) {
        let doc = document
        let scale = displayScale
        let outer = styledRect

        if doc.hasStyling {
            if BackgroundPresets.fillBackdrop(id: doc.backgroundPresetID, in: context, rect: outer, flipped: true) {
                // backdrop drawn
            } else if let color = doc.backgroundColor {
                context.setFillColor(CGColor(red: color.red, green: color.green, blue: color.blue, alpha: color.alpha))
                context.fill(outer)
            } else if doc.padding > 0 && presentation == .editor {
                Self.drawCheckerboard(in: outer, context: context)
            }
        }

        let isEditor = presentation == .editor
        let corner = doc.hasStyling ? CGFloat(doc.cornerRadius) * scale : (isEditor ? 6 : 0)
        let cardPath = CGPath(roundedRect: iRect, cornerWidth: min(corner, iRect.width / 2), cornerHeight: min(corner, iRect.height / 2), transform: nil)

        // Shadow: the user's styled shadow, or a subtle studio shadow when unstyled
        let shadowBlur = doc.hasStyling ? CGFloat(doc.shadowRadius) * scale : (isEditor ? 18 : 0)
        if shadowBlur > 0 {
            context.saveGState()
            context.setShadow(offset: CGSize(width: 0, height: -shadowBlur * 0.35), blur: shadowBlur, color: NSColor.black.withAlphaComponent(0.45).cgColor)
            context.addPath(cardPath)
            context.setFillColor(NSColor.black.cgColor)
            context.fillPath()
            context.restoreGState()
        }

        context.saveGState()
        context.addPath(cardPath)
        context.clip()
        if let img = previewImage ?? previewBaseImage ?? baseCGImage {
            context.interpolationQuality = .high
            // CGContext draws images y-up; flip locally inside the image rect
            context.translateBy(x: iRect.minX, y: iRect.maxY)
            context.scaleBy(x: 1, y: -1)
            context.draw(img, in: CGRect(origin: .zero, size: iRect.size))
        }
        context.restoreGState()

        if !doc.hasStyling && isEditor {
            context.addPath(cardPath)
            context.setStrokeColor(NSColor(white: 1.0, alpha: 0.12).cgColor)
            context.setLineWidth(1)
            context.strokePath()
        }
    }

    private static func drawCheckerboard(in rect: CGRect, context: CGContext) {
        context.saveGState()
        context.clip(to: rect)
        context.setFillColor(NSColor(white: 0.30, alpha: 1).cgColor)
        context.fill(rect)
        context.setFillColor(NSColor(white: 0.22, alpha: 1).cgColor)
        let size: CGFloat = 10
        var y = rect.minY
        var row = 0
        while y < rect.maxY {
            var x = rect.minX + (row % 2 == 0 ? 0 : size)
            while x < rect.maxX {
                context.fill(CGRect(x: x, y: y, width: size, height: size))
                x += size * 2
            }
            y += size
            row += 1
        }
        context.restoreGState()
    }

    private func drawInProgressItem(from start: CGPoint, to current: CGPoint, in context: CGContext) {
        let rect = CGRect(x: min(start.x, current.x), y: min(start.y, current.y), width: abs(current.x - start.x), height: abs(current.y - start.y))

        switch currentTool {
        case .blur, .pixelate:
            context.saveGState()
            context.setFillColor(NSColor.black.withAlphaComponent(0.35).cgColor)
            context.fill(rect)
            context.setStrokeColor(NSColor.white.cgColor)
            context.setLineWidth(1.0)
            context.setLineDash(phase: 0, lengths: [4, 4])
            context.stroke(rect)
            context.restoreGState()
            return
        default:
            break
        }

        let type: AnnotationType
        var points: [NormalizedPoint]?
        switch currentTool {
        case .rectangle: type = .rectangle
        case .ellipse: type = .ellipse
        case .highlight: type = .highlight
        case .arrow:
            type = .arrow
            points = [normalize(point: start), normalize(point: current)]
        case .freehand:
            type = .freehand
            points = freehandPoints
        default: return
        }

        let normOrigin = normalize(point: rect.origin)
        let normMax = normalize(point: CGPoint(x: rect.maxX, y: rect.maxY))
        let preview = AnnotationItem(
            type: type,
            bounds: NormalizedRect(x: normOrigin.x, y: normOrigin.y, width: normMax.x - normOrigin.x, height: normMax.y - normOrigin.y),
            strokeColor: state.color,
            strokeWidth: state.strokeWidth,
            points: points
        )
        renderer.draw(preview, in: context)
    }

    private func drawSelection(for item: AnnotationItem, in context: CGContext) {
        let r = renderer
        context.saveGState()
        defer { context.restoreGState() }

        context.setStrokeColor(Self.selectionColor.cgColor)
        context.setFillColor(NSColor.white.cgColor)
        context.setLineWidth(1.5)

        if item.type == .arrow, let pts = item.points, pts.count >= 2 {
            for p in pts.prefix(2) {
                let c = r.point(for: p)
                let handleRect = CGRect(x: c.x - 5, y: c.y - 5, width: 10, height: 10)
                context.fillEllipse(in: handleRect)
                context.strokeEllipse(in: handleRect)
            }
            return
        }

        let rect = r.rect(for: item.bounds).insetBy(dx: -4, dy: -4)
        context.setLineDash(phase: 0, lengths: [4, 3])
        context.stroke(rect)
        context.setLineDash(phase: 0, lengths: [])

        guard supportsResizeHandles(item) else { return }
        let s = Self.handleSize
        for (_, c) in handlePoints(for: r.rect(for: item.bounds)) {
            let handleRect = CGRect(x: c.x - s / 2, y: c.y - s / 2, width: s, height: s)
            context.fill(handleRect)
            context.stroke(handleRect)
        }
    }

    private func drawToastOverlay(_ text: String, in context: CGContext) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let textSize = (text as NSString).size(withAttributes: attrs)
        let toastRect = CGRect(x: bounds.midX - (textSize.width + 32) / 2, y: bounds.maxY - 56, width: textSize.width + 32, height: 36)
        let toastPath = NSBezierPath(roundedRect: toastRect, xRadius: 18, yRadius: 18)

        context.saveGState()
        NSColor.black.withAlphaComponent(0.85).setFill()
        context.setShadow(offset: CGSize(width: 0, height: -4), blur: 12, color: NSColor.black.withAlphaComponent(0.35).cgColor)
        toastPath.fill()
        context.restoreGState()

        NSColor(white: 1.0, alpha: 0.20).setStroke()
        toastPath.lineWidth = 1.0
        toastPath.stroke()

        (text as NSString).draw(at: CGPoint(x: toastRect.minX + 16, y: toastRect.minY + (toastRect.height - textSize.height) / 2), withAttributes: attrs)
    }

    // MARK: - Coordinate Transformations

    private func normalize(point: CGPoint) -> NormalizedPoint {
        let iRect = imageRect
        guard iRect.width > 0, iRect.height > 0 else { return NormalizedPoint(x: 0, y: 0) }
        return NormalizedPoint(x: (point.x - iRect.minX) / iRect.width, y: (point.y - iRect.minY) / iRect.height)
    }
}
