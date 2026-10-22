import AppKit
import CoreGraphics
import Combine

/// Interactive AppKit canvas view for drawing, in-place text editing, selecting, and manipulating annotations over a base image.
public final class AnnotationCanvasView: NSView, NSTextFieldDelegate {
    public override var isFlipped: Bool { true }

    public var baseCGImage: CGImage? {
        didSet {
            updateProcessedDisplayImage()
            needsDisplay = true
        }
    }

    public let undoRedoManager: UndoRedoManager
    public var currentTool: EditorTool = .arrow {
        didSet {
            updateCursorForCurrentTool()
            dismissInlineTextEditor()
        }
    }

    public var currentStrokeColor: AnnotationColor = .red {
        didSet {
            updateSelectedAnnotationStyle()
        }
    }

    public var currentStrokeWidth: Double = 3.0 {
        didSet {
            updateSelectedAnnotationStyle()
        }
    }

    public var currentFontSize: Double = 22.0 {
        didSet {
            updateSelectedAnnotationText()
        }
    }

    public var currentBlurRadius: Double = 20.0 {
        didSet {
            updateSelectedAnnotationBlurRadius()
        }
    }

    /// Processed base image with live blur and pixelation applied
    private var processedDisplayImage: CGImage?

    // Drawing state
    private var startPoint: CGPoint?
    private var currentDragPoint: CGPoint?
    private var freehandPoints: [NormalizedPoint] = []
    private var isDrawing = false

    // Moving / Dragging existing items state
    public var selectedItemId: UUID?
    private var isDraggingItem = false
    private var dragMouseStartPoint: CGPoint?
    private var dragItemInitialOrigin: NormalizedPoint?
    private var dragItemInitialPoints: [NormalizedPoint]?

    // Inline Text Editing
    private var activeInlineTextField: NSTextField?
    private var activeEditingTextItem: AnnotationItem?

    // Floating Toast Notification
    private var toastMessage: String?
    private var toastTimer: Timer?

    // Action Callbacks
    public var onCopyRequested: (() -> Void)?
    public var onSaveRequested: (() -> Void)?
    public var onToolChanged: ((EditorTool) -> Void)?

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Aspect-Fit Image Rect with Studio Padding

    /// Calculates the aspect-fit rectangle of the base screenshot centered with 24px margin.
    public var imageRect: CGRect {
        guard let base = baseCGImage else { return bounds }
        let margin: CGFloat = 24.0
        let availableBounds = bounds.insetBy(dx: margin, dy: margin)

        let imgW = CGFloat(base.width)
        let imgH = CGFloat(base.height)
        guard imgW > 0, imgH > 0, availableBounds.width > 0, availableBounds.height > 0 else { return bounds }

        let scale = min(availableBounds.width / imgW, availableBounds.height / imgH)
        let fitW = floor(imgW * scale)
        let fitH = floor(imgH * scale)
        let fitX = floor(availableBounds.minX + (availableBounds.width - fitW) / 2.0)
        let fitY = floor(availableBounds.minY + (availableBounds.height - fitH) / 2.0)
        return CGRect(x: fitX, y: fitY, width: fitW, height: fitH)
    }

    public init(frame: NSRect, undoRedoManager: UndoRedoManager, baseImage: CGImage? = nil) {
        self.undoRedoManager = undoRedoManager
        self.baseCGImage = baseImage
        super.init(frame: frame)

        updateProcessedDisplayImage()

        // Observe document changes to keep live blur and canvas in sync
        undoRedoManager.$document
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateProcessedDisplayImage()
                self?.needsDisplay = true
            }
            .store(in: &cancellables)

        // Tracking area for mouse movements and cursor updates
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseMoved, .cursorUpdate],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override var acceptsFirstResponder: Bool { true }

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

    // MARK: - Keyboard Handling

    public override func keyDown(with event: NSEvent) {
        let isCmd = event.modifierFlags.contains(.command)
        let isShift = event.modifierFlags.contains(.shift)
        let key = event.charactersIgnoringModifiers?.lowercased()

        // Cmd+C -> Copy
        if isCmd && key == "c" {
            onCopyRequested?()
            showToast("✓ Copied to Clipboard")
            return
        }

        // Cmd+S -> Save
        if isCmd && key == "s" {
            onSaveRequested?()
            return
        }

        // Cmd+Z -> Undo / Redo
        if isCmd && key == "z" {
            if isShift {
                undoRedoManager.redo()
            } else {
                undoRedoManager.undo()
            }
            needsDisplay = true
            return
        }

        // Delete / Backspace key to remove selected item
        if event.keyCode == 51 || event.keyCode == 117 {
            if let selectedId = selectedItemId {
                undoRedoManager.removeItem(id: selectedId)
                selectedItemId = nil
                updateProcessedDisplayImage()
                needsDisplay = true
                return
            }
        }

        // Single-key tool shortcuts (when not editing text)
        if activeInlineTextField == nil && !isCmd {
            switch key {
            case "v": switchTool(.select)
            case "a": switchTool(.arrow)
            case "r": switchTool(.rectangle)
            case "o": switchTool(.ellipse)
            case "p": switchTool(.freehand)
            case "h": switchTool(.highlight)
            case "t": switchTool(.text)
            case "b": switchTool(.blur)
            case "x": switchTool(.pixelate)
            default: super.keyDown(with: event)
            }
            return
        }

        super.keyDown(with: event)
    }

    private func switchTool(_ tool: EditorTool) {
        currentTool = tool
        onToolChanged?(tool)
        needsDisplay = true
    }

    // MARK: - Live Blur Redaction Processing

    public func updateProcessedDisplayImage() {
        guard let base = baseCGImage else {
            processedDisplayImage = nil
            return
        }

        let redactionItems = undoRedoManager.document.items.filter { $0.type == .blur || $0.type == .pixelation }
        guard !redactionItems.isEmpty else {
            processedDisplayImage = base
            return
        }

        var current = base
        let imgW = Double(base.width)
        let imgH = Double(base.height)

        for item in redactionItems {
            let pixelRect = CGRect(
                x: item.bounds.origin.x * imgW,
                y: item.bounds.origin.y * imgH,
                width: item.bounds.width * imgW,
                height: item.bounds.height * imgH
            )

            if item.type == .blur {
                current = RedactionRenderer.shared.applyBlur(to: current, in: pixelRect, radius: item.blurRadius ?? 20.0)
            } else {
                current = RedactionRenderer.shared.applyPixelation(to: current, in: pixelRect, scale: item.blurRadius ?? 16.0)
            }
        }

        processedDisplayImage = current
    }

    // MARK: - Mouse Events (Selecting, In-Place Text, Moving, and Drawing)

    public override func mouseDown(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        let iRect = imageRect

        // If clicking outside an active inline text editor, commit it
        if let textField = activeInlineTextField {
            if !textField.frame.contains(loc) {
                commitInlineTextEditor()
            }
            return
        }

        guard iRect.contains(loc) else {
            selectedItemId = nil
            needsDisplay = true
            return
        }

        // Double-click check for editing existing text
        if event.clickCount == 2, let hitItem = findItem(at: loc), hitItem.type == .text {
            startInlineTextEditor(for: hitItem, at: denormalize(rect: hitItem.bounds))
            return
        }

        // 1. Text Tool Click -> Spawn in-place text editor directly where clicked
        if currentTool == .text {
            startNewInlineTextEditor(at: loc)
            return
        }

        // 2. Check if clicking on an existing annotation to select or move it
        if let hitItem = findItem(at: loc) {
            selectedItemId = hitItem.id
            isDraggingItem = true
            dragMouseStartPoint = loc
            dragItemInitialOrigin = hitItem.bounds.origin
            dragItemInitialPoints = hitItem.points
            isDrawing = false

            currentStrokeColor = hitItem.strokeColor
            currentStrokeWidth = hitItem.strokeWidth
            if let r = hitItem.blurRadius {
                currentBlurRadius = r
            }

            needsDisplay = true
            return
        }

        // 3. Click outside any existing item in Select mode -> deselect
        if currentTool == .select {
            selectedItemId = nil
            needsDisplay = true
            return
        }

        // 4. Start drawing a new shape / arrow / redact
        selectedItemId = nil
        startPoint = loc
        currentDragPoint = loc
        isDrawing = true

        if currentTool == .freehand {
            freehandPoints = [normalize(point: loc)]
        }

        needsDisplay = true
    }

    public override func mouseDragged(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)

        // Handle moving an already selected item
        if isDraggingItem, let selectedId = selectedItemId,
           let start = dragMouseStartPoint, let initOrigin = dragItemInitialOrigin,
           let itemIndex = undoRedoManager.document.items.firstIndex(where: { $0.id == selectedId }) {

            let iRect = imageRect
            guard iRect.width > 0, iRect.height > 0 else { return }

            let deltaX = (loc.x - start.x) / iRect.width
            let deltaY = (loc.y - start.y) / iRect.height

            var item = undoRedoManager.document.items[itemIndex]
            let newX = max(0.0, min(1.0 - item.bounds.width, initOrigin.x + deltaX))
            let newY = max(0.0, min(1.0 - item.bounds.height, initOrigin.y + deltaY))
            item.bounds.origin = NormalizedPoint(x: newX, y: newY)

            if let initPoints = dragItemInitialPoints {
                item.points = initPoints.map { pt in
                    NormalizedPoint(
                        x: max(0.0, min(1.0, pt.x + deltaX)),
                        y: max(0.0, min(1.0, pt.y + deltaY))
                    )
                }
            }

            undoRedoManager.updateItem(item)

            if item.type == .blur || item.type == .pixelation {
                updateProcessedDisplayImage()
            }

            needsDisplay = true
            return
        }

        guard isDrawing else { return }
        currentDragPoint = loc

        if currentTool == .freehand {
            freehandPoints.append(normalize(point: loc))
        }

        needsDisplay = true
    }

    public override func mouseUp(with event: NSEvent) {
        if isDraggingItem {
            isDraggingItem = false
            dragMouseStartPoint = nil
            dragItemInitialOrigin = nil
            dragItemInitialPoints = nil
            updateProcessedDisplayImage()
            needsDisplay = true
            return
        }

        guard isDrawing, let start = startPoint, let current = currentDragPoint else { return }
        isDrawing = false

        let normStart = normalize(point: start)
        let normCurrent = normalize(point: current)

        if abs(normCurrent.x - normStart.x) > 0.005 || abs(normCurrent.y - normStart.y) > 0.005 || currentTool == .freehand {
            let normRect = NormalizedRect(
                x: min(normStart.x, normCurrent.x),
                y: min(normStart.y, normCurrent.y),
                width: abs(normCurrent.x - normStart.x),
                height: abs(normCurrent.y - normStart.y)
            )
            commitAnnotation(normRect: normRect, startPoint: normStart, endPoint: normCurrent)
        }

        startPoint = nil
        currentDragPoint = nil
        freehandPoints.removeAll()
        needsDisplay = true
    }

    // MARK: - In-Place Text Editor Spawning

    private func startNewInlineTextEditor(at loc: CGPoint) {
        dismissInlineTextEditor()

        let initialFrame = NSRect(x: loc.x, y: loc.y, width: 220, height: max(CGFloat(currentFontSize) + 12, 34))
        let textField = createConfiguredTextField(frame: initialFrame)
        textField.placeholderString = "Type text..."

        addSubview(textField)
        window?.makeFirstResponder(textField)
        self.activeInlineTextField = textField
        self.activeEditingTextItem = nil
    }

    private func startInlineTextEditor(for item: AnnotationItem, at rect: CGRect) {
        dismissInlineTextEditor()

        let frame = NSRect(x: rect.origin.x, y: rect.origin.y, width: max(rect.width, 180), height: max(rect.height, 34))
        let textField = createConfiguredTextField(frame: frame)
        textField.stringValue = item.textContent ?? ""

        addSubview(textField)
        window?.makeFirstResponder(textField)
        self.activeInlineTextField = textField
        self.activeEditingTextItem = item
    }

    private func createConfiguredTextField(frame: NSRect) -> NSTextField {
        let tf = NSTextField(frame: frame)
        tf.font = NSFont.systemFont(ofSize: CGFloat(currentFontSize), weight: .semibold)
        let cgColor = CGColor(
            red: CGFloat(currentStrokeColor.red),
            green: CGFloat(currentStrokeColor.green),
            blue: CGFloat(currentStrokeColor.blue),
            alpha: 1.0
        )
        tf.textColor = NSColor(cgColor: cgColor) ?? .white
        tf.isBezeled = true
        tf.bezelStyle = .roundedBezel
        tf.backgroundColor = NSColor.black.withAlphaComponent(0.65)
        tf.focusRingType = .exterior
        tf.delegate = self
        return tf
    }

    private func commitInlineTextEditor() {
        guard let tf = activeInlineTextField else { return }
        let text = tf.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

        if !text.isEmpty {
            let font = NSFont.systemFont(ofSize: CGFloat(currentFontSize), weight: .semibold)
            let textSize = (text as NSString).size(withAttributes: [.font: font])
            let boxW = max(textSize.width + 12, 40)
            let boxH = max(textSize.height + 6, 24)

            let normOrigin = normalize(point: CGPoint(x: tf.frame.minX, y: tf.frame.minY))
            let iRect = imageRect
            let normW = boxW / iRect.width
            let normH = boxH / iRect.height
            let normRect = NormalizedRect(x: normOrigin.x, y: normOrigin.y, width: normW, height: normH)

            if let existing = activeEditingTextItem {
                var updated = existing
                updated.textContent = text
                updated.bounds = normRect
                undoRedoManager.updateItem(updated)
            } else {
                let newItem = AnnotationItem(
                    type: .text,
                    bounds: normRect,
                    strokeColor: currentStrokeColor,
                    textContent: text,
                    fontSize: currentFontSize
                )
                undoRedoManager.addItem(newItem)
                selectedItemId = newItem.id
            }
        }

        dismissInlineTextEditor()
        needsDisplay = true
    }

    private func dismissInlineTextEditor() {
        if let tf = activeInlineTextField {
            tf.removeFromSuperview()
            activeInlineTextField = nil
            activeEditingTextItem = nil
            window?.makeFirstResponder(self)
        }
    }

    public func controlTextDidEndEditing(_ obj: Notification) {
        commitInlineTextEditor()
    }

    // MARK: - Annotation Commit

    private func commitAnnotation(normRect: NormalizedRect, startPoint: NormalizedPoint, endPoint: NormalizedPoint) {
        let itemType: AnnotationType
        var blurRad: Double? = nil
        var pointsToStore: [NormalizedPoint]? = nil

        switch currentTool {
        case .arrow:
            itemType = .arrow
            pointsToStore = [startPoint, endPoint]
        case .rectangle:
            itemType = .rectangle
        case .ellipse:
            itemType = .ellipse
        case .highlight:
            itemType = .highlight
        case .blur:
            itemType = .blur
            blurRad = currentBlurRadius
        case .pixelate:
            itemType = .pixelation
            blurRad = currentBlurRadius
        case .freehand:
            itemType = .freehand
            pointsToStore = freehandPoints
        default:
            return
        }

        let item = AnnotationItem(
            type: itemType,
            bounds: normRect,
            strokeColor: currentStrokeColor,
            strokeWidth: currentStrokeWidth,
            points: pointsToStore,
            blurRadius: blurRad
        )

        undoRedoManager.addItem(item)
        selectedItemId = item.id

        if item.type == .blur || item.type == .pixelation {
            updateProcessedDisplayImage()
        }
    }

    private func findItem(at point: CGPoint) -> AnnotationItem? {
        for item in undoRedoManager.document.items.reversed() {
            if item.type == .arrow, let pts = item.points, pts.count >= 2 {
                let p0 = denormalize(point: pts[0])
                let p1 = denormalize(point: pts[1])
                let minX = min(p0.x, p1.x) - 10
                let maxX = max(p0.x, p1.x) + 10
                let minY = min(p0.y, p1.y) - 10
                let maxY = max(p0.y, p1.y) + 10
                let arrowBox = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
                if arrowBox.contains(point) {
                    return item
                }
            } else {
                let rect = denormalize(rect: item.bounds)
                if rect.insetBy(dx: -6, dy: -6).contains(point) {
                    return item
                }
            }
        }
        return nil
    }

    private func updateSelectedAnnotationStyle() {
        guard let selectedId = selectedItemId,
              let item = undoRedoManager.document.items.first(where: { $0.id == selectedId }) else { return }
        var updated = item
        updated.strokeColor = currentStrokeColor
        updated.strokeWidth = currentStrokeWidth
        undoRedoManager.updateItem(updated)
        needsDisplay = true
    }

    private func updateSelectedAnnotationText() {
        guard let selectedId = selectedItemId,
              let item = undoRedoManager.document.items.first(where: { $0.id == selectedId }),
              item.type == .text else { return }
        var updated = item
        updated.fontSize = currentFontSize
        undoRedoManager.updateItem(updated)
        needsDisplay = true
    }

    private func updateSelectedAnnotationBlurRadius() {
        guard let selectedId = selectedItemId,
              let item = undoRedoManager.document.items.first(where: { $0.id == selectedId }),
              (item.type == .blur || item.type == .pixelation) else { return }
        var updated = item
        updated.blurRadius = currentBlurRadius
        undoRedoManager.updateItem(updated)
        updateProcessedDisplayImage()
        needsDisplay = true
    }

    // MARK: - Drawing (Studio Backdrop, Floating Card Shadow, and Vector Layers)

    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // 1. Draw Sleek Dark Studio Canvas Backdrop
        NSColor(calibratedRed: 0.11, green: 0.11, blue: 0.13, alpha: 1.0).setFill()
        dirtyRect.fill()

        let iRect = imageRect
        guard iRect.width > 0, iRect.height > 0 else { return }

        // 2. Draw Floating Card Ambient Drop Shadow
        context.saveGState()
        let shadowColor = NSColor.black.withAlphaComponent(0.40).cgColor
        context.setShadow(offset: CGSize(width: 0, height: -6), blur: 18, color: shadowColor)
        let roundedCard = NSBezierPath(roundedRect: iRect, xRadius: 8, yRadius: 8)
        NSColor.black.setFill()
        roundedCard.fill()
        context.restoreGState()

        // 3. Draw Screenshot inside rounded border
        context.saveGState()
        roundedCard.addClip()

        if let displayImg = processedDisplayImage ?? baseCGImage {
            let nsImage = NSImage(cgImage: displayImg, size: iRect.size)
            nsImage.draw(in: iRect)
        }
        context.restoreGState()

        // Crisp 1px card border
        NSColor(white: 1.0, alpha: 0.12).setStroke()
        roundedCard.lineWidth = 1.0
        roundedCard.stroke()

        // 4. Draw committed annotations
        for item in undoRedoManager.document.items {
            drawItem(item, in: context)
        }

        // 5. Draw active in-progress shape
        if isDrawing, let start = startPoint, let current = currentDragPoint {
            drawInProgressItem(from: start, to: current, in: context)
        }

        // 6. Draw Toast HUD if active
        if let toast = toastMessage {
            drawToastOverlay(toast, in: context)
        }
    }

    private func drawToastOverlay(_ text: String, in context: CGContext) {
        let font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white
        ]
        let textSize = (text as NSString).size(withAttributes: attrs)

        let toastW = textSize.width + 32
        let toastH: CGFloat = 36
        let toastX = bounds.midX - toastW / 2
        let toastY = bounds.maxY - 56

        let toastRect = CGRect(x: toastX, y: toastY, width: toastW, height: toastH)
        let toastPath = NSBezierPath(roundedRect: toastRect, xRadius: 18, yRadius: 18)

        context.saveGState()
        NSColor.black.withAlphaComponent(0.85).setFill()
        context.setShadow(offset: CGSize(width: 0, height: -4), blur: 12, color: NSColor.black.withAlphaComponent(0.35).cgColor)
        toastPath.fill()
        context.restoreGState()

        // Subtle border
        NSColor(white: 1.0, alpha: 0.20).setStroke()
        toastPath.lineWidth = 1.0
        toastPath.stroke()

        let textPoint = CGPoint(x: toastX + 16, y: toastY + (toastH - textSize.height) / 2)
        (text as NSString).draw(at: textPoint, withAttributes: attrs)
    }

    private func drawItem(_ item: AnnotationItem, in context: CGContext) {
        let rect = denormalize(rect: item.bounds)
        context.saveGState()

        let strokeCG = CGColor(
            red: CGFloat(item.strokeColor.red),
            green: CGFloat(item.strokeColor.green),
            blue: CGFloat(item.strokeColor.blue),
            alpha: CGFloat(item.strokeColor.alpha)
        )
        context.setStrokeColor(strokeCG)
        context.setLineWidth(CGFloat(item.strokeWidth))
        context.setLineCap(.round)
        context.setLineJoin(.round)

        switch item.type {
        case .rectangle:
            context.stroke(rect)
        case .ellipse:
            context.strokeEllipse(in: rect)
        case .arrow:
            if let pts = item.points, pts.count >= 2 {
                drawDynamicArrow(from: denormalize(point: pts[0]), to: denormalize(point: pts[1]), strokeColor: strokeCG, lineWidth: CGFloat(item.strokeWidth), context: context)
            } else {
                drawDynamicArrow(from: CGPoint(x: rect.minX, y: rect.minY), to: CGPoint(x: rect.maxX, y: rect.maxY), strokeColor: strokeCG, lineWidth: CGFloat(item.strokeWidth), context: context)
            }
        case .highlight:
            let highlightColor = CGColor(
                red: CGFloat(item.strokeColor.red),
                green: CGFloat(item.strokeColor.green),
                blue: CGFloat(item.strokeColor.blue),
                alpha: 0.35
            )
            context.setFillColor(highlightColor)
            context.fill(rect)
        case .blur, .pixelation:
            // Handled via live image processing; draw border when selected
            if selectedItemId == item.id {
                context.setStrokeColor(NSColor.systemBlue.cgColor)
                context.setLineWidth(1.5)
                context.stroke(rect)
            }
        case .freehand:
            if let points = item.points, points.count > 1 {
                let p0 = denormalize(point: points[0])
                context.move(to: p0)
                for i in 1..<points.count {
                    context.addLine(to: denormalize(point: points[i]))
                }
                context.strokePath()
            }
        case .text:
            if let text = item.textContent {
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: CGFloat(item.fontSize ?? 22.0), weight: .semibold),
                    .foregroundColor: NSColor(cgColor: strokeCG) ?? .red
                ]
                (text as NSString).draw(in: rect, withAttributes: attrs)
            }
        }

        // Draw selection handles if this item is selected
        if selectedItemId == item.id {
            drawSelectionBorder(around: rect, in: context)
        }

        context.restoreGState()
    }

    private func drawInProgressItem(from start: CGPoint, to current: CGPoint, in context: CGContext) {
        let rect = CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )

        context.saveGState()
        let strokeCG = CGColor(
            red: CGFloat(currentStrokeColor.red),
            green: CGFloat(currentStrokeColor.green),
            blue: CGFloat(currentStrokeColor.blue),
            alpha: CGFloat(currentStrokeColor.alpha)
        )
        context.setStrokeColor(strokeCG)
        context.setLineWidth(CGFloat(currentStrokeWidth))
        context.setLineCap(.round)

        switch currentTool {
        case .rectangle:
            context.stroke(rect)
        case .ellipse:
            context.strokeEllipse(in: rect)
        case .arrow:
            drawDynamicArrow(from: start, to: current, strokeColor: strokeCG, lineWidth: CGFloat(currentStrokeWidth), context: context)
        case .highlight:
            let highlightColor = CGColor(
                red: CGFloat(currentStrokeColor.red),
                green: CGFloat(currentStrokeColor.green),
                blue: CGFloat(currentStrokeColor.blue),
                alpha: 0.35
            )
            context.setFillColor(highlightColor)
            context.fill(rect)
        case .blur, .pixelate:
            context.setFillColor(NSColor.black.withAlphaComponent(0.35).cgColor)
            context.fill(rect)
            context.setStrokeColor(NSColor.white.cgColor)
            context.setLineWidth(1.0)
            context.setLineDash(phase: 0, lengths: [4, 4])
            context.stroke(rect)
        case .freehand:
            if freehandPoints.count > 1 {
                let p0 = denormalize(point: freehandPoints[0])
                context.move(to: p0)
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

    private func drawSelectionBorder(around rect: CGRect, in context: CGContext) {
        context.setStrokeColor(NSColor.systemBlue.cgColor)
        context.setLineWidth(1.5)
        context.setLineDash(phase: 0, lengths: [4, 3])
        let insetRect = rect.insetBy(dx: -4, dy: -4)
        context.stroke(insetRect)

        // Draw 4 corner handles
        context.setLineDash(phase: 0, lengths: [])
        context.setFillColor(NSColor.white.cgColor)
        let handleSize: CGFloat = 8.0
        let corners = [
            CGPoint(x: insetRect.minX - handleSize/2, y: insetRect.minY - handleSize/2),
            CGPoint(x: insetRect.maxX - handleSize/2, y: insetRect.minY - handleSize/2),
            CGPoint(x: insetRect.minX - handleSize/2, y: insetRect.maxY - handleSize/2),
            CGPoint(x: insetRect.maxX - handleSize/2, y: insetRect.maxY - handleSize/2)
        ]
        for c in corners {
            let handleRect = CGRect(origin: c, size: CGSize(width: handleSize, height: handleSize))
            context.fill(handleRect)
            context.stroke(handleRect)
        }
    }

    private func drawDynamicArrow(from start: CGPoint, to end: CGPoint, strokeColor: CGColor, lineWidth: CGFloat, context: CGContext) {
        let length = hypot(end.x - start.x, end.y - start.y)
        guard length > 2 else { return }

        let angle = atan2(end.y - start.y, end.x - start.x)
        let headLength: CGFloat = max(lineWidth * 3.5, 14.0)
        let headAngle: CGFloat = .pi / 6.0

        let bodyEnd = CGPoint(
            x: end.x - (headLength * 0.6) * cos(angle),
            y: end.y - (headLength * 0.6) * sin(angle)
        )

        context.move(to: start)
        context.addLine(to: bodyEnd)
        context.strokePath()

        let p1 = CGPoint(
            x: end.x - headLength * cos(angle - headAngle),
            y: end.y - headLength * sin(angle - headAngle)
        )
        let p2 = CGPoint(
            x: end.x - headLength * cos(angle + headAngle),
            y: end.y - headLength * sin(angle + headAngle)
        )

        context.setFillColor(strokeColor)
        context.move(to: end)
        context.addLine(to: p1)
        context.addLine(to: p2)
        context.closePath()
        context.fillPath()
    }

    private func updateCursorForCurrentTool() {
        switch currentTool {
        case .select: NSCursor.arrow.set()
        case .text: NSCursor.iBeam.set()
        default: NSCursor.crosshair.set()
        }
    }

    // MARK: - Coordinate Transformations

    private func normalize(point: CGPoint) -> NormalizedPoint {
        let iRect = imageRect
        guard iRect.width > 0, iRect.height > 0 else {
            return NormalizedPoint(x: 0, y: 0)
        }
        let nx = (point.x - iRect.origin.x) / iRect.width
        let ny = (point.y - iRect.origin.y) / iRect.height
        return NormalizedPoint(x: nx, y: ny)
    }

    private func denormalize(point: NormalizedPoint) -> CGPoint {
        let iRect = imageRect
        return CGPoint(
            x: iRect.origin.x + point.x * iRect.width,
            y: iRect.origin.y + point.y * iRect.height
        )
    }

    private func denormalize(rect: NormalizedRect) -> CGRect {
        let iRect = imageRect
        return CGRect(
            x: iRect.origin.x + rect.origin.x * iRect.width,
            y: iRect.origin.y + rect.origin.y * iRect.height,
            width: rect.width * iRect.width,
            height: rect.height * iRect.height
        )
    }
}
