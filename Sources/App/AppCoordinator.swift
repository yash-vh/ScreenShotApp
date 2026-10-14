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

    public func openEditor(for asset: ScreenshotAsset) {
        AppLogger.shared.editor.info("Opening editor for asset: \(asset.title, privacy: .public)")
        // Milestone 2 opens preview / reveals file in Finder; Milestone 3 hooks into the vector annotation canvas
        NSWorkspace.shared.open(asset.originalFileURL)
    }

    public func openPrivacySettings() {
        PermissionManager.shared.openScreenRecordingSystemSettings()
    }

    public func hasScreenCapturePermission() -> Bool {
        return PermissionManager.shared.checkScreenRecordingPermission()
    }

    // MARK: - Capture Handlers (Powered by CaptureCoordinator)

    private func startRegionCapture() {
        CaptureCoordinator.shared.captureRegion()
    }

    private func startFullScreenCapture() {
        CaptureCoordinator.shared.captureFullScreen()
    }

    private func startWindowCapture() {
        CaptureCoordinator.shared.captureWindow()
    }

    private func toggleScreenRecording() {
        isRecordingActive.toggle()
        AppLogger.shared.recording.info("Screen recording state changed: active = \(self.isRecordingActive)")
    }

    private func startOcrCapture() {
        AppLogger.shared.recognition.debug("Starting OCR capture mode.")
        CaptureCoordinator.shared.captureRegion()
    }
}
