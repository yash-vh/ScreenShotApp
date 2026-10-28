import AppKit
import CoreGraphics

/// Overlay controller for interactive window selection
@MainActor
public final class WindowSelectionOverlayController: NSObject {
    public static let shared = WindowSelectionOverlayController()

    private var overlayWindows: [NSWindow] = []
    private var isCursorPushed = false
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

        NSApp.activate(ignoringOtherApps: true)

        let keyScreen = OverlayWindow.screenUnderMouse
        for screen in NSScreen.screens {
            let window = OverlayWindow(screen: screen)

            let view = WindowHoverSelectionView(frame: NSRect(origin: .zero, size: screen.frame.size), screen: screen) { [weak self] windowId in
                self?.handleWindowSelected(windowId)
            } onCancel: { [weak self] in
                self?.handleCancel()
            }

            window.contentView = view
            overlayWindows.append(window)
            if screen == keyScreen {
                window.makeKeyAndOrderFront(nil)
            } else {
                window.orderFrontRegardless()
            }
            window.makeFirstResponder(view)
            view.refreshHover()
        }
        NSCursor.pointingHand.push()
        isCursorPushed = true
    }

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

    private func handleWindowSelected(_ windowId: CGWindowID) {
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
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
            rect: .zero,
            options: [.activeAlways, .mouseMoved, .inVisibleRect],
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
        refreshHover()
    }

    /// Re-evaluates which window is under the pointer (also called on present, before any movement)
    func refreshHover() {
        findWindowUnderCursor(at: NSEvent.mouseLocation)
    }

    override func mouseDown(with event: NSEvent) {
        if let windowId = hoveredWindowId {
            onSelect(windowId)
        } else {
            onCancel()
        }
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: // Esc
            onCancel()
        case 36, 76, 49: // Return / Enter / Space capture the highlighted window
            if let windowId = hoveredWindowId { onSelect(windowId) }
        default:
            super.keyDown(with: event)
        }
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel()
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
        let ownPID = Int(ProcessInfo.processInfo.processIdentifier)

        // Mouse point in CG coordinates (0,0 is primary display top-left)
        let primaryScreenHeight = NSScreen.screens.first?.frame.height ?? 0
        let cgMousePoint = CGPoint(x: mousePoint.x, y: primaryScreenHeight - mousePoint.y)

        for winInfo in windowInfoList {
            guard let boundsDict = winInfo[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                  let winId = winInfo[kCGWindowNumber as String] as? CGWindowID,
                  let layer = winInfo[kCGWindowLayer as String] as? Int,
                  layer == 0, // Regular application windows are at layer 0
                  (winInfo[kCGWindowOwnerPID as String] as? Int) != ownPID,
                  rect.width > 40, rect.height > 40 else { continue }

            if rect.contains(cgMousePoint) {
                if hoveredWindowId != winId || hoveredWindowFrame != rect {
                    hoveredWindowFrame = rect
                    hoveredWindowId = winId
                    needsDisplay = true
                }
                return
            }
        }

        if hoveredWindowId != nil {
            hoveredWindowFrame = nil
            hoveredWindowId = nil
            needsDisplay = true
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
