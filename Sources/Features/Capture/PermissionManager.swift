import Foundation
import CoreGraphics
import AppKit

/// Manages macOS Screen Recording and Microphone permission states
@MainActor
public final class PermissionManager: ObservableObject {
    public static let shared = PermissionManager()

    public enum PermissionStatus: String, Sendable {
        case authorized
        case denied
        case notDetermined
    }

    @Published public private(set) var screenRecordingStatus: PermissionStatus = .notDetermined

    private init() {
        checkScreenRecordingPermission()
    }

    /// Checks if screen recording access is granted
    @discardableResult
    public func checkScreenRecordingPermission() -> Bool {
        let authorized = CGPreflightScreenCaptureAccess()
        screenRecordingStatus = authorized ? .authorized : .denied
        return authorized
    }

    /// Displays a prominent modal alert explaining why permission is required with a direct link to macOS System Settings
    public func showScreenRecordingPermissionDialog() {
        // Trigger system request
        _ = CGRequestScreenCaptureAccess()

        // Present native macOS Alert modal
        let alert = NSAlert()
        alert.messageText = "Screen Recording Permission Required"
        alert.informativeText = "ScreenshotApp requires permission to capture your screen, windows, and selected areas.\n\nPlease grant access in:\nSystem Settings > Privacy & Security > Screen Recording,\nthen enable ScreenshotApp."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")

        // Ensure the app is active and brought to front so modal is immediately visible
        NSApp.activate(ignoringOtherApps: true)

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            openScreenRecordingSystemSettings()
        }
    }

    /// Directs the user to macOS System Settings > Privacy & Security > Screen Recording
    public func openScreenRecordingSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Directs the user to macOS System Settings > Privacy & Security > Microphone
    public func openMicrophoneSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }
}
