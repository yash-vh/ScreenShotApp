import AppKit
import CoreGraphics
import Combine

/// Tool mode for interactive canvas drawing
public enum EditorTool: String, CaseIterable, Identifiable {
    case select = "Select"
    case arrow = "Arrow"
    case rectangle = "Rectangle"
    case ellipse = "Ellipse"
    case freehand = "Pen"
    case highlight = "Highlight"
    case text = "Text"
    case blur = "Blur Redact"
    case pixelate = "Pixelate"

    public var id: String { rawValue }

    public var systemIcon: String {
        switch self {
        case .select: return "arrow.up.left.and.arrow.down.right"
        case .arrow: return "arrow.up.right"
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .freehand: return "pencil.line"
        case .highlight: return "highlighter"
        case .text: return "textformat"
        case .blur: return "drop.fill"
        case .pixelate: return "checkerboard.rectangle"
        }
    }
}

/// Interactive AppKit canvas view for drawing, selecting, and manipulating annotations over a base image.
public final class AnnotationCanvasView: NSView {
    public override var isFlipped: Bool { true }

    public var baseCGImage: CGImage? {
        didSet {
            updateProcessedDisplayImage()
            needsDisplay = true
        }
    }

    public let undoRedoManager: UndoRedoManager
    public var currentTool: EditorTool = .arrow
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
    public var currentTextContent: String = "Text" {
        didSet {
            updateSelectedAnnotationText()
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

    /// Processed base image with live blur and pixelation applied (Bug 7 Fix)
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

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Aspect-Fit Image Rect (Bug 1 & Bug 2 Fix)

    /// Calculates the aspect-fit rectangle of the base screenshot within the canvas bounds.
    /// Prevents image stretching and content clipping on resize.
    public var imageRect: CGRect {
        guard let base = baseCGImage else { return bounds }
        let imgW = CGFloat(base.width)
        let imgH = CGFloat(base.height)
        guard imgW > 0, imgH > 0, bounds.width > 0, bounds.height > 0 else { return bounds }

        let scale = min(bounds.width / imgW, bounds.height / imgH)
        let fitW = floor(imgW * scale)
        let fitH = floor(imgH * scale)
        let fitX = floor((bounds.width - fitW) / 2.0)
        let fitY = floor((bounds.height - fitH) / 2.0)
        return CGRect(x: fitX, y: fitY, width: fitW, height: fitH)
    }

    public init(frame: NSRect, undoRedoManager: UndoRedoManager, baseImage: CGImage? = nil) {
        self.undoRedoManager = undoRedoManager
        self.baseCGImage = baseImage
        super.init(frame: frame)

        updateProcessedDisplayImage()

        // Observe document changes to keep live blur and canvas in sync (Bug 3 & 7 Fix)
        undoRedoManager.$document
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateProcessedDisplayImage()
                self?.needsDisplay = true
            }
            .store(in: &cancellables)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override var acceptsFirstResponder: Bool { true }

    // MARK: - Keyboard Shortcuts (Bug 3 Fix: Undo/Redo with Cmd+Z, Ctrl+Z, Ctrl+Y, Cmd+Shift+Z)

    public override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let isCmd = flags.contains(.command)
        let isCtrl = flags.contains(.control)
        let isShift = flags.contains(.shift)

        // Handle Cmd+Z / Ctrl+Z (Undo)
        if (isCmd || isCtrl) && event.charactersIgnoringModifiers?.lowercased() == "z" {
            if isShift {
                undoRedoManager.redo()
            } else {
                undoRedoManager.undo()
            }
            needsDisplay = true
            return
        }

        // Handle Cmd+Y / Ctrl+Y (Redo)
        if (isCmd || isCtrl) && event.charactersIgnoringModifiers?.lowercased() == "y" {
            undoRedoManager.redo()
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

        super.keyDown(with: event)
    }

    // MARK: - Live Blur Redaction Processing (Bug 7 Fix)

    /// Computes and caches live blur and pixelation on the display image so they appear in real-time.
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

    // MARK: - Mouse Events (Selecting, Moving, and Drawing Annotations)

    public override func mouseDown(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        let iRect = imageRect

        guard iRect.contains(loc) else {
            selectedItemId = nil
            needsDisplay = true
            return
        }

        // 1. Check if clicking on an existing annotation to select or move it
        if let hitItem = findItem(at: loc) {
            selectedItemId = hitItem.id
            isDraggingItem = true
            dragMouseStartPoint = loc
            dragItemInitialOrigin = hitItem.bounds.origin
            dragItemInitialPoints = hitItem.points
            isDrawing = false

            // Sync toolbar properties with selected item
            currentStrokeColor = hitItem.strokeColor
            currentStrokeWidth = hitItem.strokeWidth
            if hitItem.type == .text {
                currentTextContent = hitItem.textContent ?? "Text"
                currentFontSize = hitItem.fontSize ?? 22.0
            } else if hitItem.type == .blur || hitItem.type == .pixelation {
                if let r = hitItem.blurRadius {
                    currentBlurRadius = r
                }
            }

            needsDisplay = true
            return
        }

        // 2. Click outside any existing item
        if currentTool == .select {
            selectedItemId = nil
            needsDisplay = true
            return
        }

        // 3. Start drawing a new item
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

        // Handle moving an already selected item anywhere on the canvas
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

            // If item has points (like arrow or pen), offset them as well
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

        // Handle in-progress drawing of a new item
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
        let normRect: NormalizedRect

        if currentTool == .text && abs(normCurrent.x - normStart.x) <= 0.005 && abs(normCurrent.y - normStart.y) <= 0.005 {
            // Click to place text box at cursor
            normRect = NormalizedRect(
                x: min(max(normStart.x, 0.0), 0.75),
                y: min(max(normStart.y, 0.0), 0.90),
                width: 0.25,
                height: 0.08
            )
            commitAnnotation(normRect: normRect, startPoint: normStart, endPoint: normCurrent)
        } else if abs(normCurrent.x - normStart.x) > 0.005 || abs(normCurrent.y - normStart.y) > 0.005 || currentTool == .freehand {
            normRect = NormalizedRect(
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

    private func commitAnnotation(normRect: NormalizedRect, startPoint: NormalizedPoint, endPoint: NormalizedPoint) {
        let itemType: AnnotationType
        var blurRad: Double? = nil
        var pointsToStore: [NormalizedPoint]? = nil
        var textToStore: String? = nil
        var fontSizeToStore: Double? = nil

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
        case .text:
            itemType = .text
            textToStore = currentTextContent.isEmpty ? "Text" : currentTextContent
            fontSizeToStore = currentFontSize
        default:
            return
        }

        let item = AnnotationItem(
            type: itemType,
            bounds: normRect,
            strokeColor: currentStrokeColor,
            strokeWidth: currentStrokeWidth,
            textContent: textToStore,
            fontSize: fontSizeToStore,
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
        updated.textContent = currentTextContent
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

    // MARK: - Drawing (Aspect-Fit, Live Blur, Dynamic Arrows, and Selection Indicators)

    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // 1. Draw Canvas Backdrop
        NSColor(calibratedWhite: 0.12, alpha: 1.0).setFill()
        dirtyRect.fill()

        let iRect = imageRect
        guard iRect.width > 0, iRect.height > 0 else { return }

        // 2. Draw Aspect-Preserved Base Screenshot (Live Blurred or Original)
        if let displayImg = processedDisplayImage ?? baseCGImage {
            let nsImage = NSImage(cgImage: displayImg, size: iRect.size)
            nsImage.draw(in: iRect)
        }

        // Draw clean border around the screenshot
        NSColor(white: 0.25, alpha: 0.8).setStroke()
        let borderPath = NSBezierPath(rect: iRect)
        borderPath.lineWidth = 1.0
        borderPath.stroke()

        // 3. Draw committed annotations
        for item in undoRedoManager.document.items {
            drawItem(item, in: context)
        }

        // 4. Draw active in-progress shape
        if isDrawing, let start = startPoint, let current = currentDragPoint {
            drawInProgressItem(from: start, to: current, in: context)
        }
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

        let isSelected = (item.id == selectedItemId)

        switch item.type {
        case .rectangle:
            context.stroke(rect)
        case .ellipse:
            context.strokeEllipse(in: rect)
        case .arrow:
            if let pts = item.points, pts.count >= 2 {
                let p0 = denormalize(point: pts[0])
                let p1 = denormalize(point: pts[1])
                drawArrow(from: p0, to: p1, in: context, color: strokeCG, lineWidth: CGFloat(item.strokeWidth))
            } else {
                drawArrow(from: CGPoint(x: rect.minX, y: rect.minY), to: CGPoint(x: rect.maxX, y: rect.maxY), in: context, color: strokeCG, lineWidth: CGFloat(item.strokeWidth))
            }
        case .highlight:
            context.setFillColor(strokeCG.copy(alpha: 0.35)!)
            context.fill(rect)
        case .blur, .pixelation:
            // Focus Area Boundary Border (Live blur is in the image, outline shows focus region)
            let path = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
            path.lineWidth = 1.5
            let pattern: [CGFloat] = [4, 4]
            path.setLineDash(pattern, count: 2, phase: 0)
            (isSelected ? NSColor.systemBlue : NSColor.white.withAlphaComponent(0.85)).setStroke()
            path.stroke()
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

        // Draw selection halo with drag handles if selected
        if isSelected {
            drawSelectionFrame(for: item, in: context)
        }

        context.restoreGState()
    }

    private func drawSelectionFrame(for item: AnnotationItem, in context: CGContext) {
        let rect = denormalize(rect: item.bounds)
        let handleRect = rect.insetBy(dx: -4, dy: -4)

        context.saveGState()
        context.setStrokeColor(NSColor.systemBlue.cgColor)
        context.setLineWidth(1.5)
        let dashPattern: [CGFloat] = [4, 3]
        context.setLineDash(phase: 0, lengths: dashPattern)
        context.stroke(handleRect)

        // Draw 4 corner handles
        context.setFillColor(NSColor.systemBlue.cgColor)
        let handleSize: CGFloat = 6.0
        let corners = [
            CGPoint(x: handleRect.minX - handleSize/2, y: handleRect.minY - handleSize/2),
            CGPoint(x: handleRect.maxX - handleSize/2, y: handleRect.minY - handleSize/2),
            CGPoint(x: handleRect.minX - handleSize/2, y: handleRect.maxY - handleSize/2),
            CGPoint(x: handleRect.maxX - handleSize/2, y: handleRect.maxY - handleSize/2)
        ]
        for corner in corners {
            context.fill(CGRect(origin: corner, size: CGSize(width: handleSize, height: handleSize)))
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

        switch currentTool {
        case .rectangle:
            context.stroke(rect)
        case .ellipse:
            context.strokeEllipse(in: rect)
        case .arrow:
            drawArrow(from: start, to: current, in: context, color: strokeCG, lineWidth: CGFloat(currentStrokeWidth))
        case .highlight:
            context.setFillColor(strokeCG.copy(alpha: 0.35)!)
            context.fill(rect)
        case .blur, .pixelate:
            // Live focus area preview
            let path = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
            path.lineWidth = 1.5
            let pattern: [CGFloat] = [4, 4]
            path.setLineDash(pattern, count: 2, phase: 0)
            NSColor.systemBlue.setStroke()
            path.stroke()
            NSColor.systemBlue.withAlphaComponent(0.20).setFill()
            path.fill()
        case .freehand:
            if freehandPoints.count > 1 {
                let p0 = denormalize(point: freehandPoints[0])
                context.move(to: p0)
                for pt in freehandPoints.dropFirst() {
                    context.addLine(to: denormalize(point: pt))
                }
                context.strokePath()
            }
        case .text:
            let path = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
            path.lineWidth = 1.0
            let pattern: [CGFloat] = [3, 3]
            path.setLineDash(pattern, count: 2, phase: 0)
            NSColor.systemBlue.setStroke()
            path.stroke()
            let txt = currentTextContent.isEmpty ? "Text" : currentTextContent
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: CGFloat(currentFontSize), weight: .semibold),
                .foregroundColor: NSColor(cgColor: strokeCG) ?? .red
            ]
            (txt as NSString).draw(in: rect, withAttributes: attrs)
        default:
            break
        }

        context.restoreGState()
    }

    private func drawArrow(from start: CGPoint, to end: CGPoint, in context: CGContext, color: CGColor, lineWidth: CGFloat) {
        context.move(to: start)
        context.addLine(to: end)
        context.strokePath()

        // Arrow head calculation
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

    // MARK: - Aspect-Preserving Coordinate Transformations

    private func normalize(point: CGPoint) -> NormalizedPoint {
        let iRect = imageRect
        guard iRect.width > 0, iRect.height > 0 else { return NormalizedPoint(x: 0, y: 0) }
        let clampedX = min(max(point.x, iRect.minX), iRect.maxX)
        let clampedY = min(max(point.y, iRect.minY), iRect.maxY)
        let nx = (clampedX - iRect.origin.x) / iRect.width
        let ny = (clampedY - iRect.origin.y) / iRect.height
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
