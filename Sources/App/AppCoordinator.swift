import AppKit
import SwiftUI
import Combine

/// Capture action type identifier
public enum CaptureActionType: String, Sendable, CaseIterable {
    case region = "Selected Region"
    case fullScreen = "Full Screen"
    case window = "Window"
    case recording = "Screen Recording"
    case ocr = "OCR Text from Screen"

    public var systemIcon: String {
        switch self {
        case .region: return "crop"
        case .fullScreen: return "macwindow"
        case .window: return "macwindow.on.rectangle"
        case .recording: return "record.circle"
        case .ocr: return "text.viewfinder"
        }
    }
}

/// Central application orchestrator managing workflow between capture, editor, and UI windows.
@MainActor
public final class AppCoordinator: ObservableObject {
    public static let shared = AppCoordinator()

    @Published public var isRecordingActive = false
    @Published public var isCapturing = false
    @Published public var recentAssets: [ScreenshotAsset] = []
    @Published public var lastErrorMessage: String?

    private var settingsWindowController: NSWindowController?

    private init() {
        AppLogger.shared.app.info("AppCoordinator initialized.")
    }

    // MARK: - Actions

    public func triggerCapture(type: CaptureActionType) {
        AppLogger.shared.capture.info("Triggered capture action: \(type.rawValue, privacy: .public)")

        // Check screen capture permissions
        if !hasScreenCapturePermission() {
            AppLogger.shared.capture.notice("Screen capture permission not yet authorized. Directing user to System Settings.")
            openPrivacySettings()
            return
        }

        switch type {
        case .region:
            startRegionCapture()
        case .fullScreen:
            startFullScreenCapture()
        case .window:
            startWindowCapture()
        case .recording:
            toggleScreenRecording()
        case .ocr:
            startOcrCapture()
        }
    }

    public func openSettings() {
        if settingsWindowController == nil {
            let settingsView = SettingsView()
                .environmentObject(AppConfiguration.shared)
                .environmentObject(self)
            
            let hostingController = NSHostingController(rootView: settingsView)
            let window = NSWindow(contentViewController: hostingController)
            window.title = "ScreenshotApp Settings"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 680, height: 500))
            window.center()
            window.isReleasedWhenClosed = false
            
            settingsWindowController = NSWindowController(window: window)
        }

        settingsWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    public func hasScreenCapturePermission() -> Bool {
        // CGPreflightScreenCaptureAccess checks if the application has permissions on macOS 10.15+
        return CGPreflightScreenCaptureAccess()
    }

    // MARK: - Capture Handlers (Foundations for M2-M6)

    private func startRegionCapture() {
        // Foundation placeholder for M2 ScreenCaptureKit region overlay
        AppLogger.shared.capture.debug("Opening region selection overlay.")
    }

    private func startFullScreenCapture() {
        // Foundation placeholder for M2 full display capture
        AppLogger.shared.capture.debug("Capturing full screen display.")
    }

    private func startWindowCapture() {
        // Foundation placeholder for M2 window selector
        AppLogger.shared.capture.debug("Capturing targeted window.")
    }

    private func toggleScreenRecording() {
        isRecordingActive.toggle()
        AppLogger.shared.recording.info("Screen recording state changed: active = \(self.isRecordingActive)")
    }

    private func startOcrCapture() {
        AppLogger.shared.recognition.debug("Starting OCR capture mode.")
    }
}
