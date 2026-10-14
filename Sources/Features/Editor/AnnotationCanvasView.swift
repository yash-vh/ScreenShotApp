import AppKit
import CoreGraphics

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
        case .blur: return "aqi.medium"
        case .pixelate: return "checkerboard.rectangle"
        }
    }
}

/// Interactive AppKit canvas view for drawing and manipulating annotations over a base image.
public final class AnnotationCanvasView: NSView {
    public var baseCGImage: CGImage? {
        didSet {
            needsDisplay = true
        }
    }

    public let undoRedoManager: UndoRedoManager
    public var currentTool: EditorTool = .arrow
    public var currentStrokeColor: AnnotationColor = .red
    public var currentStrokeWidth: Double = 3.0
    public var currentTextContent: String = "Text"

    private var startPoint: CGPoint?
    private var currentDragPoint: CGPoint?
    private var freehandPoints: [NormalizedPoint] = []
    private var isDrawing = false
    public var selectedItemId: UUID?

    public init(frame: NSRect, undoRedoManager: UndoRedoManager, baseImage: CGImage? = nil) {
        self.undoRedoManager = undoRedoManager
        self.baseCGImage = baseImage
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override var acceptsFirstResponder: Bool { true }

    // MARK: - Mouse Events

    public override func mouseDown(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        guard bounds.contains(loc) else { return }

        startPoint = loc
        currentDragPoint = loc
        isDrawing = true

        if currentTool == .freehand {
            freehandPoints = [normalize(point: loc)]
        } else if currentTool == .text {
            // Click to insert text item
            let normPoint = normalize(point: loc)
            let textItem = AnnotationItem(
                type: .text,
                bounds: NormalizedRect(origin: normPoint, width: 0.25, height: 0.08),
                strokeColor: currentStrokeColor,
                textContent: currentTextContent,
                fontSize: 22.0
            )
            undoRedoManager.addItem(textItem)
            selectedItemId = textItem.id
            isDrawing = false
        }

        needsDisplay = true
    }

    public override func mouseDragged(with event: NSEvent) {
        guard isDrawing else { return }
        let loc = convert(event.locationInWindow, from: nil)
        currentDragPoint = loc

        if currentTool == .freehand {
            freehandPoints.append(normalize(point: loc))
        }

        needsDisplay = true
    }

    public override func mouseUp(with event: NSEvent) {
        guard isDrawing, let start = startPoint, let current = currentDragPoint else { return }
        isDrawing = false

        let normStart = normalize(point: start)
        let normCurrent = normalize(point: current)
        let normRect = NormalizedRect(
            x: min(normStart.x, normCurrent.x),
            y: min(normStart.y, normCurrent.y),
            width: abs(normCurrent.x - normStart.x),
            height: abs(normCurrent.y - normStart.y)
        )

        // Ignore tiny accidental clicks
        if normRect.width > 0.005 || normRect.height > 0.005 || currentTool == .freehand {
            commitAnnotation(normRect: normRect)
        }

        startPoint = nil
        currentDragPoint = nil
        freehandPoints.removeAll()
        needsDisplay = true
    }

    private func commitAnnotation(normRect: NormalizedRect) {
        let itemType: AnnotationType
        var blurRad: Double? = nil

        switch currentTool {
        case .arrow:
            itemType = .arrow
        case .rectangle:
            itemType = .rectangle
        case .ellipse:
            itemType = .ellipse
        case .highlight:
            itemType = .highlight
        case .blur:
            itemType = .blur
            blurRad = 20.0
        case .pixelate:
            itemType = .pixelation
            blurRad = 16.0
        case .freehand:
            itemType = .freehand
        default:
            return
        }

        let item = AnnotationItem(
            type: itemType,
            bounds: normRect,
            strokeColor: currentStrokeColor,
            strokeWidth: currentStrokeWidth,
            points: currentTool == .freehand ? freehandPoints : nil,
            blurRadius: blurRad
        )

        undoRedoManager.addItem(item)
    }

    // MARK: - Drawing

    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // 1. Draw base image
        if let base = baseCGImage {
            context.draw(base, in: bounds)
        }

        // 2. Draw committed annotations
        for item in undoRedoManager.document.items {
            drawItem(item, in: context)
        }

        // 3. Draw active in-progress shape
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

        switch item.type {
        case .rectangle:
            context.stroke(rect)
        case .ellipse:
            context.strokeEllipse(in: rect)
        case .arrow:
            context.move(to: CGPoint(x: rect.minX, y: rect.minY))
            context.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            context.strokePath()
        case .highlight:
            context.setFillColor(strokeCG.copy(alpha: 0.35)!)
            context.fill(rect)
        case .blur, .pixelation:
            // Canvas overlay preview
            context.setFillColor(NSColor.black.withAlphaComponent(0.40).cgColor)
            context.fill(rect)
            context.setStrokeColor(NSColor.white.withAlphaComponent(0.80).cgColor)
            context.setLineDash(phase: 0, lengths: [4, 4])
            context.stroke(rect)
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
                    .font: NSFont.systemFont(ofSize: CGFloat(item.fontSize ?? 20.0), weight: .semibold),
                    .foregroundColor: NSColor(cgColor: strokeCG) ?? .red
                ]
                (text as NSString).draw(in: rect, withAttributes: attrs)
            }
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
        context.setStrokeColor(NSColor.systemRed.cgColor)
        context.setLineWidth(CGFloat(currentStrokeWidth))

        switch currentTool {
        case .rectangle:
            context.stroke(rect)
        case .ellipse:
            context.strokeEllipse(in: rect)
        case .arrow:
            context.move(to: start)
            context.addLine(to: current)
            context.strokePath()
        case .highlight:
            context.setFillColor(NSColor.systemYellow.withAlphaComponent(0.35).cgColor)
            context.fill(rect)
        case .blur, .pixelate:
            context.setFillColor(NSColor.black.withAlphaComponent(0.35).cgColor)
            context.fill(rect)
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

    // MARK: - Coordinate Transformations

    private func normalize(point: CGPoint) -> NormalizedPoint {
        let nx = point.x / bounds.width
        let ny = point.y / bounds.height
        return NormalizedPoint(x: nx, y: ny)
    }

    private func denormalize(point: NormalizedPoint) -> CGPoint {
        return CGPoint(x: point.x * bounds.width, y: point.y * bounds.height)
    }

    private func denormalize(rect: NormalizedRect) -> CGRect {
        return CGRect(
            x: rect.origin.x * bounds.width,
            y: rect.origin.y * bounds.height,
            width: rect.width * bounds.width,
            height: rect.height * bounds.height
        )
    }
}
