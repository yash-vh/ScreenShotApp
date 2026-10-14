import AppKit

/// Global and local keyboard shortcut listener for screenshot and recording actions.
@MainActor
public final class HotKeyManager {
    public static let shared = HotKeyManager()

    private var globalMonitor: Any?
    private var localMonitor: Any?

    private init() {}

    /// Starts monitoring for configured keyboard shortcuts
    public func startMonitoring() {
        stopMonitoring()

        // 1. Global event monitor (when another app is active)
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleKeyEvent(event)
            }
        }

        // 2. Local event monitor (when ScreenshotApp is active)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.handleKeyEvent(event) == true {
                return nil // Consume event
            }
            return event
        }

        AppLogger.shared.capture.info("Keyboard shortcut monitoring started.")
    }

    /// Stops monitoring
    public func stopMonitoring() {
        if let global = globalMonitor {
            NSEvent.removeMonitor(global)
            globalMonitor = nil
        }
        if let local = localMonitor {
            NSEvent.removeMonitor(local)
            localMonitor = nil
        }
    }

    @discardableResult
    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let hasCmdShift = flags.contains([.command, .shift])

        guard hasCmdShift, let chars = event.charactersIgnoringModifiers else {
            return false
        }

        switch chars {
        case "4":
            AppLogger.shared.capture.info("Shortcut triggered: Region Capture (⇧⌘4)")
            CaptureCoordinator.shared.captureRegion()
            return true

        case "3":
            AppLogger.shared.capture.info("Shortcut triggered: Full Screen Capture (⇧⌘3)")
            CaptureCoordinator.shared.captureFullScreen()
            return true

        case "5":
            AppLogger.shared.capture.info("Shortcut triggered: Window Capture (⇧⌘5)")
            CaptureCoordinator.shared.captureWindow()
            return true

        case "6":
            AppLogger.shared.capture.info("Shortcut triggered: Screen Recording (⇧⌘6)")
            AppCoordinator.shared.triggerCapture(type: .recording)
            return true

        case "7":
            AppLogger.shared.capture.info("Shortcut triggered: Quick OCR (⇧⌘7)")
            AppCoordinator.shared.triggerCapture(type: .ocr)
            return true

        default:
            return false
        }
    }
}
