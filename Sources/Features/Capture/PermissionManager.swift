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

    /// Prompts the system permission dialog if not yet requested
    public func requestScreenRecordingPermission() {
        CGRequestScreenCaptureAccess()
        checkScreenRecordingPermission()
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
