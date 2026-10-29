import AppKit
import SwiftUI
import Combine

/// Capture action type identifier
public enum CaptureActionType: String, Sendable, CaseIterable {
    case region = "Selected Region"
    case fullScreen = "Full Screen"
    case allScreens = "All Screens"
    case window = "Window"
    case recording = "Screen Recording"
    case ocr = "OCR Text from Screen"

    public var systemIcon: String {
        switch self {
        case .region: return "crop"
        case .fullScreen: return "macwindow"
        case .allScreens: return "rectangle.on.rectangle"
        case .window: return "macwindow.on.rectangle"
        case .recording: return "record.circle"
        case .ocr: return "text.viewfinder"
        }
    }
}

/// Central application orchestrator managing workflow between capture and UI windows.
@MainActor
public final class AppCoordinator: ObservableObject {
    public static let shared = AppCoordinator()

    @Published public var isRecordingActive = false
    @Published public var isCapturing = false
    @Published public var recentAssets: [ScreenshotAsset] = []
    @Published public var lastErrorMessage: String?

    @Published public var hasPermission: Bool = false
    @Published public var settingsTab: SettingsView.Tab = .general

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

        // Recent captures mirror the persistent history
        HistoryStore.shared.$assets
            .receive(on: DispatchQueue.main)
            .sink { [weak self] assets in
                self?.recentAssets = Array(assets.prefix(50))
            }
            .store(in: &cancellables)
        HistoryStore.shared.refreshAvailability()
        UploadService.shared.startNetworkMonitoring()
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
        hideAuxiliaryWindows()
        switch type {
        case .region:
            startRegionCapture()
        case .fullScreen:
            startFullScreenCapture()
        case .allScreens:
            CaptureCoordinator.shared.captureAllScreens()
        case .window:
            startWindowCapture()
        case .recording:
            toggleScreenRecording()
        case .ocr:
            startOcrCapture()
        }
    }

    /// Orders out any auxiliary windows (Settings, Library, Permissions) so they don't obstruct capture or pop up
    public func hideAuxiliaryWindows() {
        settingsWindowController?.window?.orderOut(nil)
        PermissionsWindowController.shared.close()
    }

    public func openSettings(tab: SettingsView.Tab? = nil) {
        if let tab {
            settingsTab = tab
        }
        if settingsWindowController == nil {
            let settingsView = SettingsView()
                .environmentObject(AppConfiguration.shared)
                .environmentObject(self)
            
            let hostingController = NSHostingController(rootView: settingsView)
            hostingController.sceneBridgingOptions = [.toolbars]
            let window = NSWindow(contentViewController: hostingController)
            window.title = "\(AppBranding.appName) Settings"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.toolbarStyle = .unified
            window.setContentSize(NSSize(width: 880, height: 620))
            window.center()
            window.isReleasedWhenClosed = false
            
            settingsWindowController = NSWindowController(window: window)

            // Title bar names the selected pane, like System Settings
            $settingsTab
                .receive(on: DispatchQueue.main)
                .sink { [weak window] tab in
                    window?.title = tab.rawValue
                    window?.subtitle = tab.subtitle
                }
                .store(in: &cancellables)
        }

        settingsWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func openLibrary() {
        LibraryWindowController.present()
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
        RecordingCoordinator.shared.toggle()
    }

    /// Starts a recording of a specific target (menu bar submenu)
    public func startRecording(_ kind: RecordingCoordinator.TargetKind) {
        guard hasScreenCapturePermission() else {
            triggerCapture(type: .recording)
            return
        }
        RecordingCoordinator.shared.start(kind)
    }

    private func startOcrCapture() {
        AppLogger.shared.recognition.debug("Starting OCR capture mode.")
        CaptureCoordinator.shared.captureText()
    }
}
