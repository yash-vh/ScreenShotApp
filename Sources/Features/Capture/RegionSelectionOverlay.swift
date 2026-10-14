import AppKit
import CoreGraphics

/// Interactive multi-display transparent overlay window controller for region selection.
@MainActor
public final class RegionSelectionOverlayController: NSObject {
    public static let shared = RegionSelectionOverlayController()

    private var overlayWindows: [NSWindow] = []
    private var onSelectionComplete: ((CGRect, NSScreen) -> Void)?
    private var onCancelled: (() -> Void)?

    private override init() {
        super.init()
    }

    /// Displays transparent fullscreen overlays across all active displays
    public func present(
        onComplete: @escaping (CGRect, NSScreen) -> Void,
        onCancel: @escaping () -> Void
    ) {
        dismiss()

        self.onSelectionComplete = onComplete
        self.onCancelled = onCancel

        for screen in NSScreen.screens {
            let window = createOverlayWindow(for: screen)
            overlayWindows.append(window)
            window.makeKeyAndOrderFront(nil)
        }

        // Set cursor to crosshair
        NSCursor.crosshair.push()
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Dismisses all overlay windows and restores mouse cursor
    public func dismiss() {
        NSCursor.pop()
        for window in overlayWindows {
            window.orderOut(nil)
        }
        overlayWindows.removeAll()
    }

    private func createOverlayWindow(for screen: NSScreen) -> NSWindow {
        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.level = .screenSaver
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = false
        window.acceptsMouseMovedEvents = true

        let selectionView = RegionSelectionView(frame: screen.frame, screen: screen) { [weak self] selectedRect in
            self?.handleSelectionComplete(selectedRect, on: screen)
        } onCancel: { [weak self] in
            self?.handleCancelled()
        }

        window.contentView = selectionView
        return window
    }

    private func handleSelectionComplete(_ rect: CGRect, on screen: NSScreen) {
        // Order out immediately so the overlay itself is not in the captured pixels
        dismiss()

        // Allow window server a brief moment to composite out overlay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.onSelectionComplete?(rect, screen)
        }
    }

    private func handleCancelled() {
        dismiss()
        onCancelled?()
    }
}

// MARK: - Region Selection View

final class RegionSelectionView: NSView {
    private let targetScreen: NSScreen
    private let onComplete: (CGRect) -> Void
    private let onCancel: () -> Void

    private var startPoint: CGPoint?
    private var currentPoint: CGPoint?
    private var isDragging = false

    init(frame: NSRect, screen: NSScreen, onComplete: @escaping (CGRect) -> Void, onCancel: @escaping () -> Void) {
        self.targetScreen = screen
        self.onComplete = onComplete
        self.onCancel = onCancel
        super.init(frame: frame)

        // Enable tracking area for mouse moves and crosshairs
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

    override var acceptsFirstResponder: Bool { true }

    // MARK: - Mouse & Key Events

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        currentPoint = startPoint
        isDragging = true
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard isDragging, let start = startPoint, let current = currentPoint else { return }
        isDragging = false

        let selectedRect = normalizedRect(from: start, to: current)
        if selectedRect.width > 5 && selectedRect.height > 5 {
            onComplete(selectedRect)
        } else {
            // Click with almost zero area cancels
            onCancel()
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // ESC key
            onCancel()
        } else if event.keyCode == 36 || event.keyCode == 49 { // Enter or Space key
            if let start = startPoint, let current = currentPoint {
                let rect = normalizedRect(from: start, to: current)
                if rect.width > 5 && rect.height > 5 {
                    onComplete(rect)
                }
            }
        }
    }

    // MARK: - Custom Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // 1. Draw darkened overlay
        context.setFillColor(NSColor.black.withAlphaComponent(0.35).cgColor)
        context.fill(bounds)

        guard let current = currentPoint else { return }

        if let start = startPoint, isDragging {
            let selectionRect = normalizedRect(from: start, to: current)

            // 2. Clear cutout hole for selected region
            context.saveGState()
            context.setBlendMode(.clear)
            context.fill(selectionRect)
            context.restoreGState()

            // 3. Selection border
            context.setStrokeColor(NSColor.white.cgColor)
            context.setLineWidth(1.5)
            context.stroke(selectionRect)

            context.setStrokeColor(NSColor.systemBlue.cgColor)
            context.setLineDash(phase: 0, lengths: [4, 4])
            context.setLineWidth(1.0)
            context.stroke(selectionRect)

            // 4. Dimension Badge (e.g. 840 × 520 px)
            drawDimensionBadge(for: selectionRect)
        } else {
            // Draw subtle crosshair lines
            drawCrosshairs(at: current, in: context)
        }
    }

    private func drawCrosshairs(at point: CGPoint, in context: CGContext) {
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.5).cgColor)
        context.setLineWidth(0.5)

        // Horizontal line
        context.move(to: CGPoint(x: 0, y: point.y))
        context.addLine(to: CGPoint(x: bounds.width, y: point.y))

        // Vertical line
        context.move(to: CGPoint(x: point.x, y: 0))
        context.addLine(to: CGPoint(x: point.x, y: bounds.height))

        context.strokePath()
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
            y: rect.minY - 26 < 10 ? rect.maxY + 8 : rect.minY - 26,
            width: textSize.width + 16,
            height: 20
        )

        let badgePath = NSBezierPath(roundedRect: badgeRect, xRadius: 4, yRadius: 4)
        NSColor.black.withAlphaComponent(0.75).setFill()
        badgePath.fill()

        let textPoint = CGPoint(x: badgeRect.origin.x + 8, y: badgeRect.origin.y + 3)
        (dimensionText as NSString).draw(at: textPoint, withAttributes: attributes)
    }

    private func normalizedRect(from p1: CGPoint, to p2: CGPoint) -> CGRect {
        let x = min(p1.x, p2.x)
        let y = min(p1.y, p2.y)
        let w = abs(p2.x - p1.x)
        let h = abs(p2.y - p1.y)
        return CGRect(x: x, y: y, width: w, height: h)
    }
}
