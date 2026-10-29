import AppKit
import SwiftUI
import Combine
import CoreGraphics

/// Action chosen by the user from the on-screen region selection toolbar
public enum RegionCaptureAction {
    case defaultAction(AnnotationDocument)
    case copy(AnnotationDocument)
    case save(AnnotationDocument)
    case upload(AnnotationDocument)
}

/// Region overlay behaviour: full annotate-and-act toolbar, or quick select-and-recognize for OCR
public enum RegionSelectionMode {
    case capture
    case quickSelect
}

/// Interactive multi-display transparent overlay window controller for region selection.
@MainActor
public final class RegionSelectionOverlayController: NSObject {
    public static let shared = RegionSelectionOverlayController()

    private var overlayWindows: [NSWindow] = []
    private var selectionViews: [RegionSelectionView] = []
    private var pointerMonitor: Any?
    private var isCursorPushed = false
    private var onSelectionComplete: ((CGRect, NSScreen, RegionCaptureAction, CGImage?) -> Void)?
    private var onCancelled: (() -> Void)?

    private override init() {
        super.init()
    }

    /// Displays transparent fullscreen overlays across all active displays
    public func present(
        mode: RegionSelectionMode = .capture,
        onComplete: @escaping (CGRect, NSScreen, RegionCaptureAction, CGImage?) -> Void,
        onCancel: @escaping () -> Void
    ) {
        dismiss()

        self.onSelectionComplete = onComplete
        self.onCancelled = onCancel

        NSApp.activate(ignoringOtherApps: true)

        let keyScreen = OverlayWindow.screenUnderMouse
        for screen in NSScreen.screens {
            let window = createOverlayWindow(for: screen, mode: mode)
            overlayWindows.append(window)
            if screen == keyScreen {
                window.makeKeyAndOrderFront(nil)
            } else {
                window.orderFrontRegardless()
            }
            window.makeFirstResponder(window.contentView)
        }

        NSCursor.crosshair.push()
        isCursorPushed = true

        // Mouse-moved events only reach the window under the pointer, so every display is told where
        // the pointer is; otherwise the screen it just left keeps drawing a stale crosshair.
        pointerMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            self?.broadcastPointer()
            return event
        }
        broadcastPointer()
    }

    private func broadcastPointer() {
        let location = NSEvent.mouseLocation
        for view in selectionViews {
            view.updatePointer(globalLocation: location)
        }
    }

    /// A new selection may start on one display only when no other display holds annotations
    fileprivate func selectionWillBegin(in source: RegionSelectionView) -> Bool {
        let others = selectionViews.filter { $0 !== source }
        guard others.allSatisfy({ !$0.hasAnnotations }) else { return false }
        others.forEach { $0.clearSelection() }
        return true
    }

    /// Dismisses all overlay windows and restores mouse cursor
    public func dismiss() {
        if let pointerMonitor {
            NSEvent.removeMonitor(pointerMonitor)
            self.pointerMonitor = nil
        }
        selectionViews.removeAll()
        if isCursorPushed {
            NSCursor.pop()
            isCursorPushed = false
        }
        for window in overlayWindows {
            window.orderOut(nil)
        }
        overlayWindows.removeAll()
    }

    private func createOverlayWindow(for screen: NSScreen, mode: RegionSelectionMode) -> NSWindow {
        let window = OverlayWindow(screen: screen)

        let displayId = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? CGMainDisplayID()
        let screenSnapshot = CGDisplayCreateImage(displayId)

        let selectionView = RegionSelectionView(
            frame: NSRect(origin: .zero, size: screen.frame.size),
            screen: screen,
            screenSnapshot: screenSnapshot,
            mode: mode
        ) { [weak self] selectedRect, action, image in
            self?.handleSelectionComplete(selectedRect, on: screen, action: action, image: image)
        } onCancel: { [weak self] in
            self?.handleCancelled()
        }

        selectionView.coordinator = self
        selectionViews.append(selectionView)
        window.contentView = selectionView
        return window
    }

    private func handleSelectionComplete(_ rect: CGRect, on screen: NSScreen, action: RegionCaptureAction, image: CGImage?) {
        dismiss()
        guard image == nil else {
            onSelectionComplete?(rect, screen, action, image)
            return
        }
        // Without a frozen snapshot, give the window server a moment to remove the overlay before re-capturing
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.onSelectionComplete?(rect, screen, action, nil)
        }
    }

    private func handleCancelled() {
        dismiss()
        onCancelled?()
    }
}

// MARK: - Region Selection View

/// Full-screen selection surface for one display.
///
/// Phase 1 draws the selection rectangle (with crosshair). Once a region is selected, the area is
/// annotated with the exact same components as the editor window: an embedded `AnnotationCanvasView`, the
/// shared `EditorToolbarView`, `UndoRedoManager` history and `RecognitionController` — so tools, styling,
/// shortcuts, move/resize and undo behave identically everywhere.
final class RegionSelectionView: NSView {
    private let targetScreen: NSScreen
    private let screenSnapshot: CGImage?
    private let mode: RegionSelectionMode
    private let onComplete: (CGRect, RegionCaptureAction, CGImage?) -> Void
    private let onCancel: () -> Void
    fileprivate weak var coordinator: RegionSelectionOverlayController?

    // Selection state (AppKit view coordinates, y-up)
    private var startPoint: CGPoint?
    private var currentPoint: CGPoint?
    private var selectionRect: CGRect = .zero
    private var hasActiveSelection = false

    private enum DragHandle {
        case topLeft, topCenter, topRight
        case middleLeft, middleRight
        case bottomLeft, bottomCenter, bottomRight
        case body
    }
    private var activeHandle: DragHandle?
    private var dragStartMouse: CGPoint?
    private var dragStartRect: CGRect?

    private var trackingArea: NSTrackingArea?

    // Shared annotation session (created when a region is selected)
    let undoRedoManager: UndoRedoManager
    let editorState = EditorState(tool: .arrow)
    private(set) var canvas: AnnotationCanvasView?
    private var toolbarHost: NSHostingView<EditorToolbarView>?
    private let chromeView = SelectionChromeView()
    private var recognition: RecognitionController?
    private var croppedSnapshot: CGImage?
    private var cancellables = Set<AnyCancellable>()

    private static let borderColor = NSColor(calibratedRed: 0.25, green: 0.65, blue: 1.0, alpha: 1.0)

    init(
        frame: NSRect,
        screen: NSScreen,
        screenSnapshot: CGImage?,
        mode: RegionSelectionMode = .capture,
        onComplete: @escaping (CGRect, RegionCaptureAction, CGImage?) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.targetScreen = screen
        self.screenSnapshot = screenSnapshot
        self.mode = mode
        self.onComplete = onComplete
        self.onCancel = onCancel
        // Annotation sizes are in points; the frozen snapshot defines how many pixels each point covers
        let pixelsPerPoint = screenSnapshot.map { Double($0.width) / Double(max(frame.width, 1)) } ?? Double(screen.backingScaleFactor)
        self.undoRedoManager = UndoRedoManager(document: AnnotationDocument(assetId: UUID(), pixelsPerPoint: pixelsPerPoint))
        super.init(frame: frame)

        chromeView.frame = bounds
        chromeView.autoresizingMask = [.width, .height]
        chromeView.drawHandler = { [weak self] context in self?.drawSelectionChrome(in: context) }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    var hasAnnotations: Bool { canvas != nil && !document.items.isEmpty }

    /// Shows the crosshair only on the display that actually contains the pointer
    func updatePointer(globalLocation: CGPoint) {
        guard !hasActiveSelection, startPoint == nil else { return }
        let frame = targetScreen.frame
        let point: CGPoint? = NSMouseInRect(globalLocation, frame, false)
            ? CGPoint(x: globalLocation.x - frame.minX, y: globalLocation.y - frame.minY)
            : nil
        guard point != currentPoint else { return }
        currentPoint = point
        needsDisplay = true
    }

    /// Drops this display's selection when the user starts selecting on another display
    func clearSelection() {
        if canvas != nil { endSession() }
        hasActiveSelection = false
        startPoint = nil
        selectionRect = .zero
        activeHandle = nil
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseMoved, .cursorUpdate, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    // MARK: - Annotation Session

    private var document: AnnotationDocument { undoRedoManager.document }

    private func startSessionIfNeeded() {
        guard canvas == nil else { return }

        let canvas = AnnotationCanvasView(frame: .zero, undoRedoManager: undoRedoManager, state: editorState, baseImage: croppedSnapshot, presentation: .embedded)
        canvas.onCopyRequested = { [weak self] in self?.finish(.copy) }
        canvas.onSaveRequested = { [weak self] in self?.finish(.save) }
        canvas.onConfirmRequested = { [weak self] in self?.finish(.copy) }
        canvas.onCloseRequested = { [weak self] in self?.cancelCapture() }
        canvas.onBackgroundDrag = { [weak self] phase, event in self?.handleBackgroundDrag(phase, event) ?? false }
        addSubview(canvas, positioned: .below, relativeTo: nil)
        self.canvas = canvas

        addSubview(chromeView)

        let toolbar = EditorToolbarView(
            undoRedoManager: undoRedoManager,
            state: editorState,
            placement: .floating,
            onUndo: { [weak canvas] in canvas?.undo(nil) },
            onRedo: { [weak canvas] in canvas?.redo(nil) },
            onDelete: { [weak canvas] in canvas?.delete(nil) },
            onCopyToClipboard: { [weak self] in self?.finish(.copy) },
            onAutoRedact: { [weak canvas] in canvas?.autoRedactSensitiveInfo() },
            secondaryActions: [
                EditorToolbarAction(id: "upload", symbol: "icloud.and.arrow.up", help: "Upload & Copy Link (⌘U)") { [weak self] in self?.finish(.upload) },
                EditorToolbarAction(id: "save", symbol: "square.and.arrow.down", help: "Save to File (⌘S)") { [weak self] in self?.finish(.save) }
            ],
            closeTitle: "Cancel",
            closeHelp: "Cancel Capture (Esc)",
            onClose: { [weak self] in self?.cancelCapture() }
        )
        let host = NSHostingView(rootView: toolbar)
        addSubview(host)
        toolbarHost = host

        recognition = RecognitionController(state: editorState, canvas: canvas) { [weak self] in self?.croppedSnapshot }

        // Styling padding changes the canvas footprint around the selection
        undoRedoManager.$document
            .map(\.padding)
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.layoutSession() }
            }
            .store(in: &cancellables)

        layoutSession()
        window?.makeFirstResponder(canvas)
    }

    private func endSession() {
        recognition?.invalidate()
        recognition = nil
        canvas?.removeFromSuperview()
        canvas = nil
        toolbarHost?.removeFromSuperview()
        toolbarHost = nil
        chromeView.removeFromSuperview()
        cancellables.removeAll()
        undoRedoManager.updateDocument(registerUndo: false) { doc in
            doc.items.removeAll()
            doc.backgroundPresetID = nil
            doc.backgroundColor = nil
            doc.padding = 0
            doc.cornerRadius = 0
            doc.shadowRadius = 0
        }
        window?.makeFirstResponder(self)
    }

    /// Positions the canvas over the selection and the toolbar beside it
    private func layoutSession(showToolbar: Bool = true) {
        guard let canvas = canvas else { return }
        let pad = CGFloat(document.padding)
        canvas.frame = selectionRect.insetBy(dx: -pad, dy: -pad)
        canvas.needsDisplay = true
        chromeView.needsDisplay = true

        guard let host = toolbarHost else { return }
        host.isHidden = !showToolbar
        let size = host.fittingSize
        let outer = canvas.frame
        var y = outer.minY - size.height - 10
        if y < 8 { y = outer.maxY + 10 }
        if y + size.height > bounds.height - 8 { y = max(8, outer.minY + 10) }
        let x = max(8, min(bounds.width - size.width - 8, outer.midX - size.width / 2))
        host.frame = CGRect(x: x, y: y, width: size.width, height: size.height)
    }

    /// Crops the frozen display snapshot to the current selection (pixels, top-left origin)
    private func updateCroppedSnapshot() {
        guard let snapshot = screenSnapshot, selectionRect.width >= 1, selectionRect.height >= 1 else {
            croppedSnapshot = nil
            return
        }
        let scale = CGFloat(snapshot.width) / bounds.width
        let pixelRect = CGRect(
            x: selectionRect.minX * scale,
            y: (bounds.height - selectionRect.maxY) * scale,
            width: selectionRect.width * scale,
            height: selectionRect.height * scale
        ).integral
        croppedSnapshot = snapshot.cropping(to: pixelRect)
        canvas?.baseCGImage = croppedSnapshot
    }

    // MARK: - Actions

    private enum FinishKind { case copy, save, upload, defaultAction }

    private func finish(_ kind: FinishKind) {
        guard hasActiveSelection, selectionRect.width > 5, selectionRect.height > 5 else {
            if !hasActiveSelection { return }
            cancelCapture()
            return
        }
        // Ending first-responder status commits any in-progress text annotation
        window?.makeFirstResponder(self)

        let doc = document

        let action: RegionCaptureAction
        switch kind {
        case .copy: action = .copy(doc)
        case .save: action = .save(doc)
        case .upload: action = .upload(doc)
        case .defaultAction: action = .defaultAction(doc)
        }

        let screenRect = CGRect(
            x: selectionRect.origin.x + targetScreen.frame.origin.x,
            y: selectionRect.origin.y + targetScreen.frame.origin.y,
            width: selectionRect.width,
            height: selectionRect.height
        )
        onComplete(screenRect, action, croppedSnapshot)
    }

    private func cancelCapture() {
        onCancel()
    }

    // MARK: - Hit Testing

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Selection resize handles take priority over the canvas underneath them
        if hasActiveSelection, mode == .capture, let handle = handleAt(point: convert(point, from: superview)), handle != .body {
            return self
        }
        return super.hitTest(point)
    }

    // MARK: - Mouse Events

    override func mouseDown(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)

        if hasActiveSelection {
            if let handle = handleAt(point: loc), handle != .body {
                window?.makeFirstResponder(self)
                beginSelectionDrag(handle, at: loc)
                return
            }
            // Clicking outside an annotated selection must not throw the annotations away
            guard document.items.isEmpty else {
                NSSound.beep()
                return
            }
            endSession()
        }

        guard coordinator?.selectionWillBegin(in: self) ?? true else {
            NSSound.beep()
            return
        }
        hasActiveSelection = false
        startPoint = loc
        currentPoint = loc
        selectionRect = .zero
        activeHandle = nil
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        currentPoint = loc

        if activeHandle != nil {
            updateSelectionDrag(to: loc)
        } else if let start = startPoint {
            selectionRect = Self.rect(from: start, to: loc).intersection(bounds)
        }
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        updatePointer(globalLocation: NSEvent.mouseLocation)
    }

    override func mouseUp(with event: NSEvent) {
        if activeHandle != nil {
            endSelectionDrag()
            return
        }

        startPoint = nil
        if selectionRect.width > 15 && selectionRect.height > 15 {
            hasActiveSelection = true
            updateCroppedSnapshot()
            if mode == .quickSelect {
                finish(.defaultAction)
                return
            }
            startSessionIfNeeded()
        } else {
            selectionRect = .zero
            cancelCapture()
        }
        needsDisplay = true
    }

    /// Select-tool drags on empty canvas space move the whole selection; a double-click copies
    private func handleBackgroundDrag(_ phase: AnnotationCanvasView.BackgroundDragPhase, _ event: NSEvent) -> Bool {
        let loc = convert(event.locationInWindow, from: nil)
        switch phase {
        case .began:
            if event.clickCount >= 2 {
                finish(.copy)
                return false
            }
            beginSelectionDrag(.body, at: loc)
        case .changed:
            updateSelectionDrag(to: loc)
            needsDisplay = true
        case .ended:
            endSelectionDrag()
        }
        return true
    }

    private func beginSelectionDrag(_ handle: DragHandle, at loc: CGPoint) {
        activeHandle = handle
        dragStartMouse = loc
        dragStartRect = selectionRect
        recognition?.invalidate()
    }

    private func updateSelectionDrag(to loc: CGPoint) {
        guard let handle = activeHandle, let startMouse = dragStartMouse, let initRect = dragStartRect else { return }
        let minSize: CGFloat = 15
        var newRect = initRect

        switch handle {
        case .body:
            newRect.origin.x = max(0, min(bounds.width - initRect.width, initRect.origin.x + loc.x - startMouse.x))
            newRect.origin.y = max(0, min(bounds.height - initRect.height, initRect.origin.y + loc.y - startMouse.y))
        default:
            var minX = initRect.minX, maxX = initRect.maxX, minY = initRect.minY, maxY = initRect.maxY
            switch handle {
            case .bottomLeft, .middleLeft, .topLeft: minX = min(loc.x, maxX - minSize)
            case .bottomRight, .middleRight, .topRight: maxX = max(loc.x, minX + minSize)
            default: break
            }
            switch handle {
            case .bottomLeft, .bottomCenter, .bottomRight: minY = min(loc.y, maxY - minSize)
            case .topLeft, .topCenter, .topRight: maxY = max(loc.y, minY + minSize)
            default: break
            }
            newRect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY).intersection(bounds)
        }

        selectionRect = newRect
        updateCroppedSnapshot()
        layoutSession(showToolbar: false)
    }

    private func endSelectionDrag() {
        activeHandle = nil
        dragStartMouse = nil
        dragStartRect = nil
        layoutSession()
        if let canvas = canvas {
            window?.makeFirstResponder(canvas)
        }
        needsDisplay = true
    }

    // MARK: - Keyboard

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard event.window == nil || event.window === window, flags.contains(.command), canvas?.isEditingText != true else {
            return super.performKeyEquivalent(with: event)
        }
        return handleCaptureShortcut(event) || super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if handleCaptureShortcut(event) { return }

        switch event.keyCode {
        case 53: // Esc
            cancelCapture()
        case 36, 76, 49: // Return / Enter / Space
            finish(.copy)
        default:
            super.keyDown(with: event)
        }
    }

    override func cancelOperation(_ sender: Any?) {
        cancelCapture()
    }

    /// Capture-level shortcuts (copy / save / upload / edit / cancel), including user-configured ones.
    /// Annotation shortcuts (tools, ⌘Z, ⌘D, ⌫, arrows…) are handled by the shared canvas.
    private func handleCaptureShortcut(_ event: NSEvent) -> Bool {
        let settings = AppConfiguration.shared.captureSettings

        for custom in settings.customShortcuts where custom.binding.matches(event: event) {
            switch custom.action {
            case "Copy Selection": finish(.copy); return true
            case "Upload & Share Link": finish(.upload); return true
            case "Cancel Capture": cancelCapture(); return true
            default: continue
            }
        }

        if settings.shortcutCancel.matches(event: event) {
            cancelCapture()
            return true
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let key = event.charactersIgnoringModifiers?.lowercased()
        let isPlainCommand = flags.contains(.command) && flags.isDisjoint(with: [.shift, .option, .control])

        if settings.shortcutCopy.matches(event: event) || (isPlainCommand && key == "c") {
            finish(.copy); return true
        }
        if settings.shortcutUpload.matches(event: event) || (isPlainCommand && key == "u") {
            finish(.upload); return true
        }
        if isPlainCommand && key == "s" {
            finish(.save); return true
        }
        return false
    }

    // MARK: - Handles

    private func handleAt(point: CGPoint) -> DragHandle? {
        guard hasActiveSelection else { return nil }
        let r = selectionRect
        let hitRadius: CGFloat = 8

        let points: [(DragHandle, CGPoint)] = [
            (.bottomLeft, CGPoint(x: r.minX, y: r.minY)),
            (.bottomCenter, CGPoint(x: r.midX, y: r.minY)),
            (.bottomRight, CGPoint(x: r.maxX, y: r.minY)),
            (.middleLeft, CGPoint(x: r.minX, y: r.midY)),
            (.middleRight, CGPoint(x: r.maxX, y: r.midY)),
            (.topLeft, CGPoint(x: r.minX, y: r.maxY)),
            (.topCenter, CGPoint(x: r.midX, y: r.maxY)),
            (.topRight, CGPoint(x: r.maxX, y: r.maxY))
        ]
        for (handle, pt) in points where abs(point.x - pt.x) <= hitRadius && abs(point.y - pt.y) <= hitRadius {
            return handle
        }
        return r.contains(point) ? .body : nil
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // 1. Dim everything except the selection
        context.setFillColor(NSColor.black.withAlphaComponent(0.38).cgColor)
        context.fill(bounds)
        if selectionRect.width > 0 && selectionRect.height > 0 {
            context.saveGState()
            context.setBlendMode(.clear)
            context.fill(selectionRect)
            context.restoreGState()
        }

        // 2. While selecting (before the canvas exists), draw the selection chrome directly
        if canvas == nil {
            drawSelectionChrome(in: context)
        }

        // 3. Crosshair while choosing the region
        if !hasActiveSelection, let current = currentPoint {
            drawProperCrosshair(at: current, in: context)
        }
    }

    /// Border, resize handles and pixel-size badge for the selection
    private func drawSelectionChrome(in context: CGContext) {
        guard selectionRect.width > 0, selectionRect.height > 0 else { return }

        context.saveGState()
        context.setStrokeColor(Self.borderColor.cgColor)
        context.setLineWidth(1.5)
        context.stroke(selectionRect)
        context.restoreGState()

        drawDimensionBadge(for: selectionRect)

        if hasActiveSelection && mode == .capture {
            drawSelectionHandles(for: selectionRect, color: Self.borderColor)
        }
    }

    private func drawProperCrosshair(at point: CGPoint, in context: CGContext) {
        context.saveGState()
        let armLength: CGFloat = 10.0

        context.setStrokeColor(NSColor.black.withAlphaComponent(0.7).cgColor)
        context.setLineWidth(2.7)
        context.move(to: CGPoint(x: point.x - armLength, y: point.y))
        context.addLine(to: CGPoint(x: point.x + armLength, y: point.y))
        context.move(to: CGPoint(x: point.x, y: point.y - armLength))
        context.addLine(to: CGPoint(x: point.x, y: point.y + armLength))
        context.strokePath()

        context.setStrokeColor(NSColor.white.cgColor)
        context.setLineWidth(1.5)
        context.move(to: CGPoint(x: point.x - armLength, y: point.y))
        context.addLine(to: CGPoint(x: point.x + armLength, y: point.y))
        context.move(to: CGPoint(x: point.x, y: point.y - armLength))
        context.addLine(to: CGPoint(x: point.x, y: point.y + armLength))
        context.strokePath()

        context.setFillColor(NSColor.systemRed.cgColor)
        context.fillEllipse(in: CGRect(x: point.x - 1.5, y: point.y - 1.5, width: 3.0, height: 3.0))
        context.restoreGState()
    }

    private func drawSelectionHandles(for rect: CGRect, color: NSColor) {
        let handleRadius: CGFloat = 4.5
        let points: [CGPoint] = [
            CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.midX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.minX, y: rect.midY), CGPoint(x: rect.maxX, y: rect.midY),
            CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.midX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY)
        ]
        for pt in points {
            let path = NSBezierPath(ovalIn: CGRect(x: pt.x - handleRadius, y: pt.y - handleRadius, width: handleRadius * 2, height: handleRadius * 2))
            NSColor.white.setFill()
            path.fill()
            color.setStroke()
            path.lineWidth = 1.5
            path.stroke()
        }
    }

    private func drawDimensionBadge(for rect: CGRect) {
        let scale = screenSnapshot.map { CGFloat($0.width) / bounds.width } ?? targetScreen.backingScaleFactor
        let dimensionText = "\(Int(rect.width * scale)) × \(Int(rect.height * scale)) px"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let textSize = (dimensionText as NSString).size(withAttributes: attributes)
        let pad = CGFloat(canvas == nil ? 0 : document.padding)
        let top = rect.maxY + pad
        let badgeRect = CGRect(
            x: rect.midX - (textSize.width + 16) / 2,
            y: top + 8 > bounds.height - 30 ? rect.minY - pad - 26 : top + 8,
            width: textSize.width + 16,
            height: 20
        )
        let badgePath = NSBezierPath(roundedRect: badgeRect, xRadius: 4, yRadius: 4)
        NSColor.black.withAlphaComponent(0.75).setFill()
        badgePath.fill()
        (dimensionText as NSString).draw(at: CGPoint(x: badgeRect.minX + 8, y: badgeRect.minY + 3), withAttributes: attributes)
    }

    private static func rect(from p1: CGPoint, to p2: CGPoint) -> CGRect {
        CGRect(x: min(p1.x, p2.x), y: min(p1.y, p2.y), width: abs(p2.x - p1.x), height: abs(p2.y - p1.y))
    }
}

/// Transparent, click-through layer drawn above the annotation canvas (selection border, handles, size badge)
private final class SelectionChromeView: NSView {
    var drawHandler: ((CGContext) -> Void)?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        drawHandler?(context)
    }
}
