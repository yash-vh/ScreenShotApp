import AppKit
import CoreGraphics

/// Overlay controller for interactive window selection
@MainActor
public final class WindowSelectionOverlayController: NSObject {
    public static let shared = WindowSelectionOverlayController()

    private var overlayWindows: [NSWindow] = []
    private var onWindowSelected: ((CGWindowID) -> Void)?
    private var onCancel: (() -> Void)?

    private override init() {
        super.init()
    }

    public func present(
        onSelect: @escaping (CGWindowID) -> Void,
        onCancel: @escaping () -> Void
    ) {
        dismiss()

        self.onWindowSelected = onSelect
        self.onCancel = onCancel

        for screen in NSScreen.screens {
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

            let view = WindowHoverSelectionView(frame: screen.frame, screen: screen) { [weak self] windowId in
                self?.handleWindowSelected(windowId)
            } onCancel: { [weak self] in
                self?.handleCancel()
            }

            window.contentView = view
            overlayWindows.append(window)
            window.makeKeyAndOrderFront(nil)
        }

        NSApp.activate(ignoringOtherApps: true)
    }

    public func dismiss() {
        for window in overlayWindows {
            window.orderOut(nil)
        }
        overlayWindows.removeAll()
    }

    private func handleWindowSelected(_ windowId: CGWindowID) {
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.onWindowSelected?(windowId)
        }
    }

    private func handleCancel() {
        dismiss()
        onCancel?()
    }
}

// MARK: - Window Hover View

final class WindowHoverSelectionView: NSView {
    private let screen: NSScreen
    private let onSelect: (CGWindowID) -> Void
    private let onCancel: () -> Void

    private var hoveredWindowFrame: CGRect?
    private var hoveredWindowId: CGWindowID?

    init(frame: NSRect, screen: NSScreen, onSelect: @escaping (CGWindowID) -> Void, onCancel: @escaping () -> Void) {
        self.screen = screen
        self.onSelect = onSelect
        self.onCancel = onCancel
        super.init(frame: frame)

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseMoved],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override func mouseMoved(with event: NSEvent) {
        let mouseLoc = NSEvent.mouseLocation
        findWindowUnderCursor(at: mouseLoc)
    }

    override func mouseDown(with event: NSEvent) {
        if let windowId = hoveredWindowId {
            onSelect(windowId)
        } else {
            onCancel()
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // ESC
            onCancel()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // Dim everything slightly
        context.setFillColor(NSColor.black.withAlphaComponent(0.20).cgColor)
        context.fill(bounds)

        // Highlight hovered window
        if let winFrame = hoveredWindowFrame {
            // Convert CGWindow global top-left coordinates to AppKit bottom-left coordinates
            let appKitRect = convertToAppKitCoordinates(cgRect: winFrame)

            context.saveGState()
            context.setBlendMode(.clear)
            context.fill(appKitRect)
            context.restoreGState()

            // Draw bright highlight border
            context.setStrokeColor(NSColor.systemBlue.cgColor)
            context.setLineWidth(3.0)
            context.stroke(appKitRect)
        }
    }

    private func findWindowUnderCursor(at mousePoint: NSPoint) {
        // Query on-screen windows via CoreGraphics
        guard let windowInfoList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return
        }

        // Mouse point in CG coordinates (0,0 is primary display top-left)
        let primaryScreenHeight = NSScreen.screens.first?.frame.height ?? 0
        let cgMousePoint = CGPoint(x: mousePoint.x, y: primaryScreenHeight - mousePoint.y)

        for winInfo in windowInfoList {
            guard let boundsDict = winInfo[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                  let winId = winInfo[kCGWindowNumber as String] as? CGWindowID,
                  let layer = winInfo[kCGWindowLayer as String] as? Int,
                  layer == 0 else { continue } // Regular application windows are at layer 0

            if rect.contains(cgMousePoint) {
                hoveredWindowFrame = rect
                hoveredWindowId = winId
                needsDisplay = true
                return
            }
        }
    }

    private func convertToAppKitCoordinates(cgRect: CGRect) -> CGRect {
        let primaryScreenHeight = NSScreen.screens.first?.frame.height ?? 0
        let appKitY = primaryScreenHeight - (cgRect.origin.y + cgRect.height)
        return CGRect(
            x: cgRect.origin.x - screen.frame.origin.x,
            y: appKitY - screen.frame.origin.y,
            width: cgRect.width,
            height: cgRect.height
        )
    }
}
