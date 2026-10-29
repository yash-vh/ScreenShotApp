import AppKit

/// Borderless full-screen overlay window that can still become key, so capture overlays
/// receive keyboard input (Esc, Return, ⌘Z, inline text typing).
final class OverlayWindow: NSWindow {
    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        setFrame(screen.frame, display: false)
        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    /// Brings ScreenMint forward so its overlay owns the cursor and keyboard. Only the active app may change
    /// the cursor; without this the app underneath keeps showing its own (I-beam over text, hand over links).
    @MainActor
    static func activateApp() {
        NSApp.activate()
        NSRunningApplication.current.activate(options: [.activateAllWindows])
    }

    /// The overlay screen currently containing the mouse pointer
    static var screenUnderMouse: NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    }
}
