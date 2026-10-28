import AppKit
import CoreGraphics

/// Action chosen by the user from the on-screen region selection toolbar
public enum RegionCaptureAction {
    case defaultAction(AnnotationDocument)
    case copy(AnnotationDocument)
    case save(AnnotationDocument)
    case edit(AnnotationDocument)
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
    private var isCursorPushed = false
    private var onSelectionComplete: ((CGRect, NSScreen, RegionCaptureAction) -> Void)?
    private var onCancelled: (() -> Void)?

    private override init() {
        super.init()
    }

    /// Displays transparent fullscreen overlays across all active displays
    public func present(
        mode: RegionSelectionMode = .capture,
        onComplete: @escaping (CGRect, NSScreen, RegionCaptureAction) -> Void,
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
    }

    /// Dismisses all overlay windows and restores mouse cursor
    public func dismiss() {
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
        ) { [weak self] selectedRect, action in
            self?.handleSelectionComplete(selectedRect, on: screen, action: action)
        } onCancel: { [weak self] in
            self?.handleCancelled()
        }

        window.contentView = selectionView
        return window
    }

    private func handleSelectionComplete(_ rect: CGRect, on screen: NSScreen, action: RegionCaptureAction) {
        dismiss()
        // Give the window server a moment to remove the overlay before the screen is captured
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.onSelectionComplete?(rect, screen, action)
        }
    }

    private func handleCancelled() {
        dismiss()
        onCancelled?()
    }
}

// MARK: - Region Selection View with In-Place Annotations, Flameshot-Style Toolbar & Handles

final class RegionSelectionView: NSView, NSTextFieldDelegate {
    private let targetScreen: NSScreen
    private let screenSnapshot: CGImage?
    private let mode: RegionSelectionMode
    private let onComplete: (CGRect, RegionCaptureAction) -> Void
    private let onCancel: () -> Void

    // Selection & Dragging State
    private var startPoint: CGPoint?
    private var currentPoint: CGPoint?
    private var selectionRect: CGRect = .zero
    private var isDragging = false
    private var hasActiveSelection = false

    // In-Place Drawing & Annotation State
    private var currentTool: EditorTool = .select
    private var activeColor: AnnotationColor = .red
    private var activeStrokeWidth: Double = 3.0
    private var document = AnnotationDocument(assetId: UUID())
    private var undoStack: [AnnotationDocument] = []
    private var redoStack: [AnnotationDocument] = []

    // In-progress drawing
    private var isDrawingAnnotation = false
    private var annotationStartPoint: CGPoint = .zero
    private var annotationCurrentPoint: CGPoint = .zero
    private var freehandPoints: [NormalizedPoint] = []

    // Resize Handles
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

    private static let textFontSize: Double = 20

    // Floating On-Screen Action & Tool Menu Bar
    private let toolbarContainer = NSView()
    private var toolButtons: [String: NSButton] = [:]

    // Inline Text Field for Direct On-Screen Typing
    private lazy var inlineTextField: NSTextField = {
        let tf = NSTextField()
        tf.font = AnnotationRenderer.font(ofSize: Self.textFontSize)
        tf.textColor = .white
        tf.backgroundColor = NSColor.black.withAlphaComponent(0.65)
        tf.isBordered = true
        tf.wantsLayer = true
        tf.layer?.cornerRadius = 5
        tf.layer?.borderColor = NSColor.systemBlue.cgColor
        tf.layer?.borderWidth = 1.5
        tf.placeholderString = "Type annotation..."
        tf.isHidden = true
        tf.target = self
        tf.action = #selector(didCommitInlineText)
        tf.delegate = self
        return tf
    }()

    init(
        frame: NSRect,
        screen: NSScreen,
        screenSnapshot: CGImage?,
        mode: RegionSelectionMode = .capture,
        onComplete: @escaping (CGRect, RegionCaptureAction) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.targetScreen = screen
        self.screenSnapshot = screenSnapshot
        self.mode = mode
        self.onComplete = onComplete
        self.onCancel = onCancel
        super.init(frame: frame)

        setupFloatingToolbar()
        addSubview(inlineTextField)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseMoved, .cursorUpdate, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        self.trackingArea = area
    }

    // MARK: - Floating Toolbar Setup (M3 Drawing Tools & M4 Actions)

    private func setupFloatingToolbar() {
        toolbarContainer.wantsLayer = true
        toolbarContainer.layer?.backgroundColor = NSColor(calibratedWhite: 0.12, alpha: 0.95).cgColor
        toolbarContainer.layer?.cornerRadius = 18
        toolbarContainer.layer?.borderWidth = 1.0
        toolbarContainer.layer?.borderColor = NSColor.white.withAlphaComponent(0.25).cgColor
        toolbarContainer.layer?.shadowColor = NSColor.black.cgColor
        toolbarContainer.layer?.shadowOpacity = 0.55
        toolbarContainer.layer?.shadowOffset = CGSize(width: 0, height: -3)
        toolbarContainer.layer?.shadowRadius = 8
        toolbarContainer.isHidden = true

        var currentX: CGFloat = 8
        let btnSize: CGFloat = 26
        let btnSpacing: CGFloat = 4

        func addToolButton(icon: String, tooltip: String, tool: EditorTool) {
            let btn = NSButton(frame: CGRect(x: currentX, y: 5, width: btnSize, height: btnSize))
            btn.bezelStyle = .regularSquare
            btn.isBordered = false
            btn.image = NSImage(systemSymbolName: icon, accessibilityDescription: tooltip)
            btn.imagePosition = .imageOnly
            btn.imageScaling = .scaleProportionallyDown
            btn.contentTintColor = .white
            btn.toolTip = tooltip
            btn.target = self
            btn.action = #selector(didSelectToolButton(_:))
            btn.identifier = NSUserInterfaceItemIdentifier(tool.rawValue)
            btn.wantsLayer = true
            toolbarContainer.addSubview(btn)
            toolButtons[tool.rawValue] = btn
            currentX += btnSize + btnSpacing
        }

        func addActionButton(icon: String, tooltip: String, action: Selector, tint: NSColor = .white) {
            let btn = NSButton(frame: CGRect(x: currentX, y: 5, width: btnSize, height: btnSize))
            btn.bezelStyle = .regularSquare
            btn.isBordered = false
            btn.image = NSImage(systemSymbolName: icon, accessibilityDescription: tooltip)
            btn.imagePosition = .imageOnly
            btn.imageScaling = .scaleProportionallyDown
            btn.contentTintColor = tint
            btn.toolTip = tooltip
            btn.target = self
            btn.action = action
            toolbarContainer.addSubview(btn)
            currentX += btnSize + btnSpacing
        }

        func addSeparator() {
            let sep = NSBox(frame: CGRect(x: currentX + 1, y: 7, width: 1, height: 22))
            sep.boxType = .separator
            toolbarContainer.addSubview(sep)
            currentX += 8
        }

        // 1. Move / Selection Mode
        addToolButton(icon: "arrow.up.and.down.and.arrow.left.and.right", tooltip: "Move & Resize Selection (V)", tool: .select)

        addSeparator()

        // 2. In-Place M3 Annotation Tools
        addToolButton(icon: "pencil.line", tooltip: "Pen (P)", tool: .freehand)
        addToolButton(icon: "arrow.up.right", tooltip: "Arrow (A)", tool: .arrow)
        addToolButton(icon: "rectangle", tooltip: "Rectangle (R)", tool: .rectangle)
        addToolButton(icon: "circle", tooltip: "Ellipse (O)", tool: .ellipse)
        addToolButton(icon: "highlighter", tooltip: "Highlighter (H)", tool: .highlight)
        addToolButton(icon: "textformat", tooltip: "Text (T)", tool: .text)
        addToolButton(icon: "drop.fill", tooltip: "Blur / Redact (B)", tool: .blur)
        addToolButton(icon: "checkerboard.rectangle", tooltip: "Pixelate (X)", tool: .pixelate)

        addSeparator()

        // 3. Undo / Redo
        addActionButton(icon: "arrow.uturn.backward", tooltip: "Undo (⌘Z)", action: #selector(didClickUndo))
        addActionButton(icon: "arrow.uturn.forward", tooltip: "Redo (⇧⌘Z)", action: #selector(didClickRedo))

        addSeparator()

        // 4. M4 Export Actions & Cancel
        addActionButton(icon: "pencil.and.outline", tooltip: "Open in Editor (⌘E)", action: #selector(didClickEdit), tint: NSColor.systemOrange)
        addActionButton(icon: "doc.on.doc.fill", tooltip: "Copy to Clipboard (⌘C / ↵)", action: #selector(didClickCopy), tint: NSColor.systemGreen)
        addActionButton(icon: "icloud.and.arrow.up.fill", tooltip: "Upload & Copy Link (⌘U)", action: #selector(didClickUpload), tint: NSColor.systemTeal)
        addActionButton(icon: "square.and.arrow.down.fill", tooltip: "Save to File (⌘S)", action: #selector(didClickSave), tint: NSColor.systemBlue)
        addActionButton(icon: "xmark.circle.fill", tooltip: "Cancel (Esc)", action: #selector(didClickCancel), tint: NSColor.systemRed)

        let totalWidth = currentX + 4
        toolbarContainer.frame = CGRect(x: 0, y: 0, width: totalWidth, height: 36)
        addSubview(toolbarContainer)

        updateActiveToolButton()
    }

    private func updateActiveToolButton() {
        for (raw, btn) in toolButtons {
            let isSelected = (currentTool.rawValue == raw)
            btn.layer?.backgroundColor = isSelected ? NSColor.systemBlue.cgColor : NSColor.clear.cgColor
            btn.layer?.cornerRadius = 6
        }
    }

    // MARK: - Toolbar Actions

    @objc private func didSelectToolButton(_ sender: NSButton) {
        commitInlineTextIfNeeded()
        if let raw = sender.identifier?.rawValue, let tool = EditorTool(rawValue: raw) {
            currentTool = tool
            updateActiveToolButton()
            needsDisplay = true
        }
    }

    @objc private func didClickUndo() {
        commitInlineTextIfNeeded()
        performUndo()
    }

    @objc private func didClickRedo() {
        commitInlineTextIfNeeded()
        performRedo()
    }

    @objc private func didClickCopy() {
        commitInlineTextIfNeeded()
        finishSelection(with: .copy(document))
    }

    @objc private func didClickEdit() {
        commitInlineTextIfNeeded()
        finishSelection(with: .edit(document))
    }

    @objc private func didClickUpload() {
        commitInlineTextIfNeeded()
        finishSelection(with: .upload(document))
    }

    @objc private func didClickSave() {
        commitInlineTextIfNeeded()
        finishSelection(with: .save(document))
    }

    @objc private func didClickCancel() {
        commitInlineTextIfNeeded()
        onCancel()
    }

    // MARK: - Undo / Redo

    private func pushUndo() {
        undoStack.append(document)
        redoStack.removeAll()
    }

    private func performUndo() {
        guard let prev = undoStack.popLast() else { return }
        redoStack.append(document)
        document = prev
        needsDisplay = true
    }

    private func performRedo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(document)
        document = next
        needsDisplay = true
    }

    private func finishSelection(with action: RegionCaptureAction) {
        guard selectionRect.width > 5 && selectionRect.height > 5 else {
            onCancel()
            return
        }

        let screenRect = CGRect(
            x: selectionRect.origin.x + targetScreen.frame.origin.x,
            y: selectionRect.origin.y + targetScreen.frame.origin.y,
            width: selectionRect.width,
            height: selectionRect.height
        )
        document.pixelsPerPoint = Double(targetScreen.backingScaleFactor)
        let finalDocument = document
        let resolved: RegionCaptureAction
        switch action {
        case .copy: resolved = .copy(finalDocument)
        case .save: resolved = .save(finalDocument)
        case .edit: resolved = .edit(finalDocument)
        case .upload: resolved = .upload(finalDocument)
        case .defaultAction: resolved = .defaultAction(finalDocument)
        }
        onComplete(screenRect, resolved)
    }

    // MARK: - Inline Text Handling

    private func commitInlineTextIfNeeded() {
        guard !inlineTextField.isHidden else { return }
        didCommitInlineText()
    }

    @objc private func didCommitInlineText() {
        let str = inlineTextField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !str.isEmpty && selectionRect.width > 0 && selectionRect.height > 0 {
            // Text bounds are anchored at the field's top-left corner (normalized space is y-down)
            let normPoint = normalize(point: CGPoint(x: inlineTextField.frame.minX, y: inlineTextField.frame.maxY))
            let size = AnnotationRenderer.textSize(str, fontSize: CGFloat(Self.textFontSize))
            let item = AnnotationItem(
                type: .text,
                bounds: NormalizedRect(origin: normPoint, width: size.width / selectionRect.width, height: size.height / selectionRect.height),
                strokeColor: activeColor,
                textContent: str,
                fontSize: Self.textFontSize
            )
            pushUndo()
            document.items.append(item)
        }
        inlineTextField.stringValue = ""
        inlineTextField.isHidden = true
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    // MARK: - Mouse Events (Drawing, Moving, Resizing)

    override func mouseDown(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)

        // Ignore clicks inside floating toolbar
        if hasActiveSelection && toolbarContainer.frame.contains(loc) {
            super.mouseDown(with: event)
            return
        }

        // Commit any active inline text
        if !inlineTextField.isHidden && !inlineTextField.frame.contains(loc) {
            commitInlineTextIfNeeded()
        }

        // Double-click inside selection confirms capture
        if hasActiveSelection && selectionRect.contains(loc) && event.clickCount >= 2 && currentTool == .select {
            finishSelection(with: .copy(document))
            return
        }

        // If selection is already active:
        if hasActiveSelection {
            if currentTool == .select {
                // Check if clicking resize handles or body
                if let handle = handleAt(point: loc) {
                    activeHandle = handle
                    dragStartMouse = loc
                    dragStartRect = selectionRect
                    isDragging = true
                    toolbarContainer.isHidden = true
                    needsDisplay = true
                    return
                }

                // Clicking outside selection resets and starts a new selection
                hasActiveSelection = false
                activeHandle = nil
                toolbarContainer.isHidden = true
                document.items.removeAll()
                undoStack.removeAll()
                redoStack.removeAll()
                startPoint = loc
                currentPoint = loc
                selectionRect = .zero
                isDragging = true
                needsDisplay = true
                return
            } else {
                // In-Place Drawing Tools (Arrow, Rect, Ellipse, Pen, Highlight, Text, Blur)
                if selectionRect.contains(loc) {
                    if currentTool == .text {
                        inlineTextField.frame = CGRect(x: loc.x, y: loc.y - 14, width: 160, height: 30)
                        inlineTextField.stringValue = ""
                        inlineTextField.isHidden = false
                        window?.makeFirstResponder(inlineTextField)
                        return
                    }

                    isDrawingAnnotation = true
                    annotationStartPoint = loc
                    annotationCurrentPoint = loc
                    if currentTool == .freehand {
                        freehandPoints = [normalize(point: loc)]
                    }
                    needsDisplay = true
                    return
                } else {
                    // Click outside during drawing switches back to select mode
                    currentTool = .select
                    updateActiveToolButton()
                    needsDisplay = true
                    return
                }
            }
        }

        // Initial selection creation
        hasActiveSelection = false
        activeHandle = nil
        toolbarContainer.isHidden = true
        startPoint = loc
        currentPoint = loc
        selectionRect = .zero
        isDragging = true
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        currentPoint = loc

        if isDrawingAnnotation {
            annotationCurrentPoint = loc
            if currentTool == .freehand {
                freehandPoints.append(normalize(point: loc))
            }
            needsDisplay = true
            return
        }

        if let handle = activeHandle, let startMouse = dragStartMouse, let initRect = dragStartRect {
            let deltaX = loc.x - startMouse.x
            let deltaY = loc.y - startMouse.y

            var newRect = initRect
            switch handle {
            case .body:
                newRect.origin.x = max(0, min(bounds.width - initRect.width, initRect.origin.x + deltaX))
                newRect.origin.y = max(0, min(bounds.height - initRect.height, initRect.origin.y + deltaY))

            case .bottomLeft:
                let newMinX = min(loc.x, initRect.maxX - 15)
                let newMinY = min(loc.y, initRect.maxY - 15)
                newRect = CGRect(x: newMinX, y: newMinY, width: initRect.maxX - newMinX, height: initRect.maxY - newMinY)

            case .bottomCenter:
                let newMinY = min(loc.y, initRect.maxY - 15)
                newRect = CGRect(x: initRect.origin.x, y: newMinY, width: initRect.width, height: initRect.maxY - newMinY)

            case .bottomRight:
                let newMaxX = max(loc.x, initRect.minX + 15)
                let newMinY = min(loc.y, initRect.maxY - 15)
                newRect = CGRect(x: initRect.minX, y: newMinY, width: newMaxX - initRect.minX, height: initRect.maxY - newMinY)

            case .middleLeft:
                let newMinX = min(loc.x, initRect.maxX - 15)
                newRect = CGRect(x: newMinX, y: initRect.origin.y, width: initRect.maxX - newMinX, height: initRect.height)

            case .middleRight:
                let newMaxX = max(loc.x, initRect.minX + 15)
                newRect = CGRect(x: initRect.minX, y: initRect.origin.y, width: newMaxX - initRect.minX, height: initRect.height)

            case .topLeft:
                let newMinX = min(loc.x, initRect.maxX - 15)
                let newMaxY = max(loc.y, initRect.minY + 15)
                newRect = CGRect(x: newMinX, y: initRect.minY, width: initRect.maxX - newMinX, height: newMaxY - initRect.minY)

            case .topCenter:
                let newMaxY = max(loc.y, initRect.minY + 15)
                newRect = CGRect(x: initRect.origin.x, y: initRect.minY, width: initRect.width, height: newMaxY - initRect.minY)

            case .topRight:
                let newMaxX = max(loc.x, initRect.minX + 15)
                let newMaxY = max(loc.y, initRect.minY + 15)
                newRect = CGRect(x: initRect.minX, y: initRect.minY, width: newMaxX - initRect.minX, height: newMaxY - initRect.minY)
            }

            selectionRect = newRect
        } else if let start = startPoint {
            selectionRect = normalizedRect(from: start, to: loc)
        }

        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if isDrawingAnnotation {
            isDrawingAnnotation = false
            commitInPlaceAnnotation()
            needsDisplay = true
            return
        }

        isDragging = false
        activeHandle = nil
        dragStartMouse = nil
        dragStartRect = nil

        if selectionRect.width > 15 && selectionRect.height > 15 {
            if mode == .quickSelect {
                finishSelection(with: .defaultAction(document))
                return
            }
            hasActiveSelection = true
            updateToolbarPosition()
            toolbarContainer.isHidden = false
        } else if !hasActiveSelection {
            toolbarContainer.isHidden = true
            onCancel()
        }

        needsDisplay = true
    }

    private func commitInPlaceAnnotation() {
        guard selectionRect.width > 0, selectionRect.height > 0 else { return }
        defer { freehandPoints.removeAll() }
        let dragDistance = hypot(annotationCurrentPoint.x - annotationStartPoint.x, annotationCurrentPoint.y - annotationStartPoint.y)
        guard currentTool == .freehand || dragDistance >= 4 else { return }

        let normStart = normalize(point: annotationStartPoint)
        let normCurrent = normalize(point: annotationCurrentPoint)
        let normRect = NormalizedRect(
            x: min(normStart.x, normCurrent.x),
            y: min(normStart.y, normCurrent.y),
            width: abs(normCurrent.x - normStart.x),
            height: abs(normCurrent.y - normStart.y)
        )

        let item: AnnotationItem
        switch currentTool {
        case .arrow:
            item = AnnotationItem(type: .arrow, bounds: normRect, strokeColor: activeColor, strokeWidth: activeStrokeWidth, points: [normStart, normCurrent])
        case .rectangle:
            item = AnnotationItem(type: .rectangle, bounds: normRect, strokeColor: activeColor, strokeWidth: activeStrokeWidth)
        case .ellipse:
            item = AnnotationItem(type: .ellipse, bounds: normRect, strokeColor: activeColor, strokeWidth: activeStrokeWidth)
        case .highlight:
            item = AnnotationItem(type: .highlight, bounds: normRect, strokeColor: AnnotationColor(red: 1.0, green: 0.95, blue: 0.10), strokeWidth: 16.0)
        case .blur:
            item = AnnotationItem(type: .blur, bounds: normRect, blurRadius: 20.0)
        case .pixelate:
            item = AnnotationItem(type: .pixelation, bounds: normRect, blurRadius: 16.0)
        case .freehand:
            guard freehandPoints.count > 1 else { return }
            item = AnnotationItem(type: .freehand, bounds: AnnotationCanvasView.boundingRect(of: freehandPoints), strokeColor: activeColor, strokeWidth: activeStrokeWidth, points: freehandPoints)
        default:
            return
        }

        pushUndo()
        document.items.append(item)
        freehandPoints.removeAll()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.window == nil || event.window === window, inlineTextField.isHidden,
              event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command) else {
            return super.performKeyEquivalent(with: event)
        }
        return handleKey(event) || super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if !handleKey(event) {
            super.keyDown(with: event)
        }
    }

    override func cancelOperation(_ sender: Any?) {
        // Esc while typing discards the text instead of the whole capture
        if !inlineTextField.isHidden {
            inlineTextField.stringValue = ""
            inlineTextField.isHidden = true
            window?.makeFirstResponder(self)
            needsDisplay = true
            return
        }
        onCancel()
    }

    /// Handles overlay shortcuts. Returns false when the key is not an overlay shortcut.
    private func handleKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let isCmd = flags.contains(.command)
        let isShift = flags.contains(.shift)
        let settings = AppConfiguration.shared.captureSettings

        // User-defined overlay shortcuts
        for custom in settings.customShortcuts where custom.binding.matches(event: event) {
            switch custom.action {
            case "Copy Selection":
                commitInlineTextIfNeeded()
                if hasActiveSelection { finishSelection(with: .copy(document)) }
                return true
            case "Upload & Share Link":
                commitInlineTextIfNeeded()
                if hasActiveSelection { finishSelection(with: .upload(document)) }
                return true
            case "Cancel Capture":
                cancelOperation(nil)
                return true
            default:
                continue
            }
        }

        // Tool shortcuts once a region is selected
        if hasActiveSelection, !isCmd, flags.isDisjoint(with: [.control, .option]),
           let key = event.charactersIgnoringModifiers?.lowercased(),
           let tool = AnnotationCanvasView.toolShortcuts[key], toolButtons[tool.rawValue] != nil {
            currentTool = tool
            updateActiveToolButton()
            needsDisplay = true
            return true
        }

        // 1. Undo / Redo
        if isCmd && event.charactersIgnoringModifiers?.lowercased() == "z" {
            if isShift {
                performRedo()
            } else {
                performUndo()
            }
            return true
        }

        // 2. Cancel Selection: Esc or configured shortcutCancel
        if event.keyCode == 53 || settings.shortcutCancel.matches(event: event) {
            cancelOperation(nil)
            return true
        }

        // 3. Copy Selection: Cmd + C, Enter, Space, or configured shortcutCopy
        if (isCmd && event.charactersIgnoringModifiers?.lowercased() == "c") ||
           settings.shortcutCopy.matches(event: event) ||
           event.keyCode == 36 || event.keyCode == 49 {
            commitInlineTextIfNeeded()
            if hasActiveSelection {
                finishSelection(with: .copy(document))
            }
            return true
        }

        // 4. Upload Selection: Cmd + U or configured shortcutUpload
        if (isCmd && event.charactersIgnoringModifiers?.lowercased() == "u") ||
           settings.shortcutUpload.matches(event: event) {
            commitInlineTextIfNeeded()
            if hasActiveSelection {
                finishSelection(with: .upload(document))
            }
            return true
        }

        // 5. Save: Cmd + S
        if isCmd && event.charactersIgnoringModifiers?.lowercased() == "s" {
            commitInlineTextIfNeeded()
            if hasActiveSelection {
                finishSelection(with: .save(document))
            }
            return true
        }

        // 6. Open in Editor: ⌘E
        if isCmd && event.charactersIgnoringModifiers?.lowercased() == "e" {
            commitInlineTextIfNeeded()
            if hasActiveSelection {
                finishSelection(with: .edit(document))
            }
            return true
        }

        return false
    }

    // MARK: - Handle Hit Testing & Positioning

    private func handleAt(point: CGPoint) -> DragHandle? {
        guard hasActiveSelection else { return nil }
        let handleHitRadius: CGFloat = 10.0

        let points: [(DragHandle, CGPoint)] = [
            (.bottomLeft, CGPoint(x: selectionRect.minX, y: selectionRect.minY)),
            (.bottomCenter, CGPoint(x: selectionRect.midX, y: selectionRect.minY)),
            (.bottomRight, CGPoint(x: selectionRect.maxX, y: selectionRect.minY)),
            (.middleLeft, CGPoint(x: selectionRect.minX, y: selectionRect.midY)),
            (.middleRight, CGPoint(x: selectionRect.maxX, y: selectionRect.midY)),
            (.topLeft, CGPoint(x: selectionRect.minX, y: selectionRect.maxY)),
            (.topCenter, CGPoint(x: selectionRect.midX, y: selectionRect.maxY)),
            (.topRight, CGPoint(x: selectionRect.maxX, y: selectionRect.maxY))
        ]

        for (handle, pt) in points {
            let hitRect = CGRect(x: pt.x - handleHitRadius, y: pt.y - handleHitRadius, width: handleHitRadius * 2, height: handleHitRadius * 2)
            if hitRect.contains(point) {
                return handle
            }
        }

        if selectionRect.contains(point) {
            return .body
        }

        return nil
    }

    private func updateToolbarPosition() {
        let toolbarW = toolbarContainer.frame.width
        let toolbarH = toolbarContainer.frame.height

        var posX = selectionRect.midX - toolbarW / 2
        posX = max(16, min(bounds.width - toolbarW - 16, posX))

        var posY = selectionRect.minY - toolbarH - 12
        if posY < 16 {
            posY = selectionRect.maxY + 12
        }
        if posY + toolbarH > bounds.height - 16 {
            posY = max(16, selectionRect.minY + 12)
        }

        toolbarContainer.frame.origin = CGPoint(x: posX, y: posY)
    }

    // MARK: - Custom Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // 1. Darkened overlay
        context.setFillColor(NSColor.black.withAlphaComponent(0.38).cgColor)
        context.fill(bounds)

        // 2. Selection Area Cutout
        if selectionRect.width > 0 && selectionRect.height > 0 {
            context.saveGState()
            context.setBlendMode(.clear)
            context.fill(selectionRect)
            context.restoreGState()

            // 3. Render In-Place Live Blur and Vector Annotations
            renderInPlaceAnnotations(in: context)

            // 4. Render In-Progress Drawing
            if isDrawingAnnotation {
                drawInProgressAnnotation(in: context)
            }

            // 5. Crisp selection border
            let borderColor = NSColor(calibratedRed: 0.25, green: 0.65, blue: 1.0, alpha: 1.0)
            context.setStrokeColor(borderColor.cgColor)
            context.setLineWidth(1.5)
            context.stroke(selectionRect)

            // 6. Dimension Badge
            drawDimensionBadge(for: selectionRect)

            // 7. 8 Circular Handles when in select/resize mode
            if hasActiveSelection && currentTool == .select {
                drawSelectionHandles(for: selectionRect, in: context, color: borderColor)
            }
        }

        // 8. Proper "+" Crosshair and Small Round Magnifier (when initially selecting)
        if !hasActiveSelection, let current = currentPoint {
            drawProperCrosshair(at: current, in: context)
            drawSmallRoundLoupe(at: current, in: context)
        }
    }

    // MARK: - In-Place Annotation Rendering

    private func renderInPlaceAnnotations(in context: CGContext) {
        guard selectionRect.width > 0, selectionRect.height > 0 else { return }

        let scale = targetScreen.backingScaleFactor

        // 1. Live Blur / Pixelate Items (snapshot pixels are top-down, view points are bottom-up)
        for item in document.items where item.type == .blur || item.type == .pixelation {
            let rect = denormalize(rect: item.bounds)
            let pixelRect = CGRect(
                x: rect.origin.x * scale,
                y: (bounds.height - (rect.origin.y + rect.height)) * scale,
                width: rect.width * scale,
                height: rect.height * scale
            ).integral

            if let snapshot = screenSnapshot, let cropped = snapshot.cropping(to: pixelRect) {
                let fullRect = CGRect(x: 0, y: 0, width: cropped.width, height: cropped.height)
                let redacted = item.type == .blur
                    ? RedactionRenderer.shared.applyBlur(to: cropped, in: fullRect, radius: item.blurRadius ?? 20.0)
                    : RedactionRenderer.shared.applyPixelation(to: cropped, in: fullRect, scale: item.blurRadius ?? 16.0)
                context.draw(redacted, in: rect)
            }

            context.saveGState()
            context.setStrokeColor(NSColor.systemBlue.withAlphaComponent(0.6).cgColor)
            context.setLineWidth(1.0)
            context.setLineDash(phase: 0, lengths: [4, 4])
            context.stroke(rect)
            context.restoreGState()
        }

        // 2. Vector layers through the shared renderer in a locally flipped (y-down) space
        context.saveGState()
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)
        let flippedSelection = CGRect(x: selectionRect.minX, y: bounds.height - selectionRect.maxY, width: selectionRect.width, height: selectionRect.height)
        let renderer = AnnotationRenderer(imageRect: flippedSelection, scale: 1)
        for item in document.items where item.type != .blur && item.type != .pixelation {
            renderer.draw(item, in: context)
        }
        context.restoreGState()
    }

    private func drawInProgressAnnotation(in context: CGContext) {
        let rect = CGRect(
            x: min(annotationStartPoint.x, annotationCurrentPoint.x),
            y: min(annotationStartPoint.y, annotationCurrentPoint.y),
            width: abs(annotationCurrentPoint.x - annotationStartPoint.x),
            height: abs(annotationCurrentPoint.y - annotationStartPoint.y)
        )

        let strokeCG = CGColor(red: CGFloat(activeColor.red), green: CGFloat(activeColor.green), blue: CGFloat(activeColor.blue), alpha: CGFloat(activeColor.alpha))

        context.saveGState()
        context.setStrokeColor(strokeCG)
        context.setLineWidth(CGFloat(activeStrokeWidth))

        switch currentTool {
        case .arrow:
            drawArrow(from: annotationStartPoint, to: annotationCurrentPoint, in: context, color: strokeCG, lineWidth: CGFloat(activeStrokeWidth))

        case .rectangle:
            context.stroke(rect)

        case .ellipse:
            context.strokeEllipse(in: rect)

        case .highlight:
            context.setFillColor(NSColor.systemYellow.withAlphaComponent(0.35).cgColor)
            context.fill(rect)

        case .blur, .pixelate:
            context.setFillColor(NSColor.systemBlue.withAlphaComponent(0.25).cgColor)
            context.fill(rect)
            context.setStrokeColor(NSColor.systemBlue.cgColor)
            let dashPattern: [CGFloat] = [4, 4]
            context.setLineDash(phase: 0, lengths: dashPattern)
            context.stroke(rect)

        case .freehand:
            if freehandPoints.count > 1 {
                context.move(to: denormalize(point: freehandPoints[0]))
                for pt in freehandPoints.dropFirst() {
                    context.addLine(to: denormalize(point: pt))
                }
                context.strokePath()
            }

        default:
            break
        }

        context.restoreGState()
    }

    private func drawArrow(from start: CGPoint, to end: CGPoint, in context: CGContext, color: CGColor, lineWidth: CGFloat) {
        context.move(to: start)
        context.addLine(to: end)
        context.strokePath()

        let angle = atan2(end.y - start.y, end.x - start.x)
        let arrowLength: CGFloat = max(14, lineWidth * 3.5)
        let arrowAngle: CGFloat = .pi / 6

        let p1 = CGPoint(
            x: end.x - arrowLength * cos(angle - arrowAngle),
            y: end.y - arrowLength * sin(angle - arrowAngle)
        )
        let p2 = CGPoint(
            x: end.x - arrowLength * cos(angle + arrowAngle),
            y: end.y - arrowLength * sin(angle + arrowAngle)
        )

        context.setFillColor(color)
        context.move(to: end)
        context.addLine(to: p1)
        context.addLine(to: p2)
        context.closePath()
        context.fillPath()
    }

    // MARK: - Proper "+" Crosshair & Small Round Magnifier

    private func drawProperCrosshair(at point: CGPoint, in context: CGContext) {
        context.saveGState()

        let armLength: CGFloat = 10.0
        let lineWidth: CGFloat = 1.5

        // Shadow outline
        context.setStrokeColor(NSColor.black.withAlphaComponent(0.7).cgColor)
        context.setLineWidth(lineWidth + 1.2)

        context.move(to: CGPoint(x: point.x - armLength, y: point.y))
        context.addLine(to: CGPoint(x: point.x + armLength, y: point.y))
        context.move(to: CGPoint(x: point.x, y: point.y - armLength))
        context.addLine(to: CGPoint(x: point.x, y: point.y + armLength))
        context.strokePath()

        // Crisp white foreground crosshair
        context.setStrokeColor(NSColor.white.cgColor)
        context.setLineWidth(lineWidth)

        context.move(to: CGPoint(x: point.x - armLength, y: point.y))
        context.addLine(to: CGPoint(x: point.x + armLength, y: point.y))
        context.move(to: CGPoint(x: point.x, y: point.y - armLength))
        context.addLine(to: CGPoint(x: point.x, y: point.y + armLength))
        context.strokePath()

        // Center tiny red precision dot
        context.setFillColor(NSColor.systemRed.cgColor)
        context.fillEllipse(in: CGRect(x: point.x - 1.5, y: point.y - 1.5, width: 3.0, height: 3.0))

        context.restoreGState()
    }

    private func drawSmallRoundLoupe(at point: CGPoint, in context: CGContext) {
        guard let snapshot = screenSnapshot else { return }

        let scale = targetScreen.backingScaleFactor
        let loupeDiameter: CGFloat = 64.0

        var posX = point.x + 20.0
        var posY = point.y + 20.0

        if posX + loupeDiameter > bounds.width - 12 {
            posX = point.x - loupeDiameter - 20.0
        }
        if posY + loupeDiameter > bounds.height - 12 {
            posY = point.y - loupeDiameter - 20.0
        }

        posX = max(10, min(bounds.width - loupeDiameter - 10, posX))
        posY = max(10, min(bounds.height - loupeDiameter - 10, posY))

        let loupeRect = CGRect(x: posX, y: posY, width: loupeDiameter, height: loupeDiameter)
        let pixelX = point.x * scale
        let pixelY = (bounds.height - point.y) * scale

        let zoom: CGFloat = 4.0
        let sampleSize = loupeDiameter / zoom
        let sampleRect = CGRect(
            x: pixelX - sampleSize / 2.0,
            y: pixelY - sampleSize / 2.0,
            width: sampleSize,
            height: sampleSize
        )

        context.saveGState()

        // Shadow
        context.setShadow(offset: CGSize(width: 0, height: -2), blur: 8, color: NSColor.black.withAlphaComponent(0.55).cgColor)

        // Background circle
        let circlePath = NSBezierPath(ovalIn: loupeRect)
        NSColor.black.setFill()
        circlePath.fill()

        context.restoreGState()

        // Clipped magnified snapshot
        context.saveGState()
        circlePath.addClip()

        if let cropped = snapshot.cropping(to: sampleRect) {
            context.interpolationQuality = .none
            context.draw(cropped, in: loupeRect)
        }

        // Center red precision dot
        context.setFillColor(NSColor.systemRed.cgColor)
        context.fillEllipse(in: CGRect(x: loupeRect.midX - 1.5, y: loupeRect.midY - 1.5, width: 3.0, height: 3.0))

        context.restoreGState()

        // Thin white border around circle
        NSColor.white.withAlphaComponent(0.95).setStroke()
        circlePath.lineWidth = 1.5
        circlePath.stroke()
    }

    // MARK: - Handles & Badges

    private func drawSelectionHandles(for rect: CGRect, in context: CGContext, color: NSColor) {
        let handleRadius: CGFloat = 4.5
        let points: [CGPoint] = [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.midX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.minX, y: rect.midY),
            CGPoint(x: rect.maxX, y: rect.midY),
            CGPoint(x: rect.minX, y: rect.maxY),
            CGPoint(x: rect.midX, y: rect.maxY),
            CGPoint(x: rect.maxX, y: rect.maxY)
        ]

        for pt in points {
            let handleRect = CGRect(x: pt.x - handleRadius, y: pt.y - handleRadius, width: handleRadius * 2, height: handleRadius * 2)
            NSColor.white.setFill()
            let path = NSBezierPath(ovalIn: handleRect)
            path.fill()
            color.setStroke()
            path.lineWidth = 1.5
            path.stroke()
        }
    }

    private func drawDimensionBadge(for rect: CGRect) {
        let scale = targetScreen.backingScaleFactor
        let pixelWidth = Int(rect.width * scale)
        let pixelHeight = Int(rect.height * scale)
        let dimensionText = "\(pixelWidth) × \(pixelHeight) px"

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let textSize = (dimensionText as NSString).size(withAttributes: attributes)

        let badgeRect = CGRect(
            x: rect.midX - (textSize.width + 16) / 2,
            y: rect.maxY + 8 > bounds.height - 30 ? rect.minY - 26 : rect.maxY + 8,
            width: textSize.width + 16,
            height: 20
        )

        let badgePath = NSBezierPath(roundedRect: badgeRect, xRadius: 4, yRadius: 4)
        NSColor.black.withAlphaComponent(0.75).setFill()
        badgePath.fill()

        let textPoint = CGPoint(x: badgeRect.origin.x + 8, y: badgeRect.origin.y + 3)
        (dimensionText as NSString).draw(at: textPoint, withAttributes: attributes)
    }

    // MARK: - Coordinate Transformations

    // Normalized annotation space is top-left origin (y-down); this view is bottom-left origin.

    private func normalize(point: CGPoint) -> NormalizedPoint {
        guard selectionRect.width > 0, selectionRect.height > 0 else { return NormalizedPoint(x: 0, y: 0) }
        let nx = (point.x - selectionRect.minX) / selectionRect.width
        let ny = (selectionRect.maxY - point.y) / selectionRect.height
        return NormalizedPoint(x: max(0.0, min(1.0, nx)), y: max(0.0, min(1.0, ny)))
    }

    private func denormalize(point: NormalizedPoint) -> CGPoint {
        return CGPoint(
            x: selectionRect.minX + point.x * selectionRect.width,
            y: selectionRect.maxY - point.y * selectionRect.height
        )
    }

    private func denormalize(rect: NormalizedRect) -> CGRect {
        return CGRect(
            x: selectionRect.minX + rect.origin.x * selectionRect.width,
            y: selectionRect.maxY - (rect.origin.y + rect.height) * selectionRect.height,
            width: rect.width * selectionRect.width,
            height: rect.height * selectionRect.height
        )
    }

    private func normalizedRect(from p1: CGPoint, to p2: CGPoint) -> CGRect {
        let x = min(p1.x, p2.x)
        let y = min(p1.y, p2.y)
        let w = abs(p2.x - p1.x)
        let h = abs(p2.y - p1.y)
        return CGRect(x: x, y: y, width: w, height: h)
    }
}
