import Foundation
import CoreGraphics
import ScreenCaptureKit
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
    @Published public private(set) var isAuthorized: Bool = false

    private init() {
        checkScreenRecordingPermission()

        // Auto-refresh permission status when app gains focus (e.g. returning from System Settings)
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.verifyScreenRecordingPermission()
            }
        }
    }

    /// Checks if screen recording access is granted synchronously via CGPreflightScreenCaptureAccess
    @discardableResult
    public func checkScreenRecordingPermission() -> Bool {
        let authorized = CGPreflightScreenCaptureAccess()
        screenRecordingStatus = authorized ? .authorized : .denied
        isAuthorized = authorized
        return authorized
    }

    /// Verifies screen recording permission with an asynchronous fallback check via ScreenCaptureKit.
    /// This resolves issues where CGPreflightScreenCaptureAccess() temporarily caches `false`
    /// even though access was granted.
    @discardableResult
    public func verifyScreenRecordingPermission() async -> Bool {
        if CGPreflightScreenCaptureAccess() {
            screenRecordingStatus = .authorized
            isAuthorized = true
            return true
        }

        // Secondary check using ScreenCaptureKit
        if #available(macOS 14.0, *) {
            do {
                _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                screenRecordingStatus = .authorized
                isAuthorized = true
                return true
            } catch {
                AppLogger.shared.capture.notice("SCShareableContent verification check: \(error.localizedDescription, privacy: .public)")
            }
        }

        // Tertiary check: attempt live trial capture directly via ScreenCaptureService
        do {
            _ = try await ScreenCaptureService.shared.captureDisplay()
            screenRecordingStatus = .authorized
            isAuthorized = true
            return true
        } catch {
            AppLogger.shared.capture.notice("ScreenCaptureService trial capture check: \(error.localizedDescription, privacy: .public)")
        }

        screenRecordingStatus = .denied
        isAuthorized = false
        return false
    }

    /// Manually marks permission as authorized when a capture succeeds
    public func markAuthorized() {
        screenRecordingStatus = .authorized
        isAuthorized = true
    }

    /// Displays an actionable dialog explaining how to grant permissions, with direct links to
    /// System Settings, Relaunch, and a Reset TCC option for clearing stale entries.
    public func showScreenRecordingPermissionDialog() {
        // If already authorized, no dialog is needed
        if checkScreenRecordingPermission() {
            return
        }

        // Trigger system permission prompt if not yet presented
        _ = CGRequestScreenCaptureAccess()

        let alert = NSAlert()
        alert.messageText = "Screen Recording Permission Required"
        alert.informativeText = """
        \(AppBranding.appName) needs permission to capture your screen, windows, and selected areas.

        If permission is ALREADY enabled in System Settings:
        1. macOS requires \(AppBranding.appName) to be quit and reopened for permissions to take effect. Click "Relaunch App" below.
        2. If it still asks after relaunching, the entry in System Settings is stale. Click "Reset Permission" to clear the stale entry, then turn the toggle back on.
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Relaunch App")
        alert.addButton(withTitle: "Reset Permission")
        alert.addButton(withTitle: "Cancel")

        NSApp.activate(ignoringOtherApps: true)

        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            openScreenRecordingSystemSettings()
        case .alertSecondButtonReturn:
            relaunchApp()
        case .alertThirdButtonReturn:
            resetScreenCapturePermission()
        default:
            break
        }
    }

    /// Resets macOS Screen Recording TCC approval status for this app.
    /// This fixes the common macOS issue where an entry in System Settings is marked enabled,
    /// but macOS rejected it due to a binary signature update during development.
    public func resetScreenCapturePermission() {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.screenmint.mac"
        AppLogger.shared.app.info("Resetting TCC ScreenCapture permission for \(bundleID, privacy: .public)")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", "ScreenCapture", bundleID]
        try? process.run()
        process.waitUntilExit()

        _ = checkScreenRecordingPermission()
        _ = CGRequestScreenCaptureAccess()
        openScreenRecordingSystemSettings()
    }

    /// Programmatically relaunches the application so macOS TCC updates take effect.
    public func relaunchApp() {
        let bundleURL = Bundle.main.bundleURL
        AppLogger.shared.app.info("Relaunching \(AppBranding.appName) from \(bundleURL.path, privacy: .public)")

        // With the relaunch agent on, a second copy would hand off to this (quitting) one and exit too,
        // leaving nothing running; let launchd restart the managed instance instead
        if BackgroundRelauncher.isAgentEnabled, BackgroundRelauncher.restartManagedInstance() {
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-n", bundleURL.path]

        do {
            try process.run()
            NSApp.terminate(nil)
        } catch {
            AppLogger.shared.app.error("Failed to relaunch \(AppBranding.appName): \(error.localizedDescription, privacy: .public)")
            let fallbackAlert = NSAlert()
            fallbackAlert.messageText = "Please Restart \(AppBranding.appName)"
            fallbackAlert.informativeText = "Please quit and reopen \(AppBranding.appName) manually from your Applications or build folder to apply permissions."
            fallbackAlert.addButton(withTitle: "Quit")
            fallbackAlert.runModal()
            NSApp.terminate(nil)
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
