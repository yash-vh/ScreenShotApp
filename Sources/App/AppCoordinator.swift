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

    @Published public var hasPermission: Bool = false

    private var settingsWindowController: NSWindowController?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        AppLogger.shared.app.info("AppCoordinator initialized.")
        self.hasPermission = PermissionManager.shared.checkScreenRecordingPermission()
        PermissionManager.shared.$isAuthorized
            .receive(on: DispatchQueue.main)
            .sink { [weak self] authorized in
                self?.hasPermission = authorized
            }
            .store(in: &cancellables)
    }

    // MARK: - Actions

    public func triggerCapture(type: CaptureActionType) {
        AppLogger.shared.capture.info("Triggered capture action: \(type.rawValue, privacy: .public)")

        // Check screen capture permissions immediately
        if hasScreenCapturePermission() {
            proceedWithCapture(type: type)
            return
        }

        // Asynchronous verification in case of stale cache
        Task { @MainActor in
            let verified = await PermissionManager.shared.verifyScreenRecordingPermission()
            if verified {
                self.proceedWithCapture(type: type)
            } else {
                AppLogger.shared.capture.notice("Screen capture permission not yet authorized. Presenting permission modal.")
                PermissionManager.shared.showScreenRecordingPermissionDialog()
            }
        }
    }

    private func proceedWithCapture(type: CaptureActionType) {
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
        EditorWindowController.present(for: asset)
    }

    public func openPrivacySettings() {
        PermissionManager.shared.openScreenRecordingSystemSettings()
    }

    public func hasScreenCapturePermission() -> Bool {
        return PermissionManager.shared.isAuthorized || PermissionManager.shared.checkScreenRecordingPermission()
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
        // Screen recording ships in Milestone 6; don't pretend a recording started
        AppLogger.shared.recording.info("Screen recording requested; not yet available.")
        CaptureHUD.shared.show(
            title: "Screen recording is coming soon",
            detail: "Video & GIF capture arrives with Milestone 6.",
            symbol: "record.circle"
        )
    }

    private func startOcrCapture() {
        AppLogger.shared.recognition.debug("Starting OCR capture mode.")
        CaptureCoordinator.shared.captureText()
    }
}
