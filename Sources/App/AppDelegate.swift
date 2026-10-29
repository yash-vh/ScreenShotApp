import AppKit
import SwiftUI
import Combine

/// AppKit application delegate handling lifecycle, menu bar instantiation, and dock visibility.
@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?
    private var cancellables = Set<AnyCancellable>()

    public func applicationDidFinishLaunching(_ notification: Notification) {
        AppLogger.shared.app.info("\(AppBranding.appName) launched successfully.")

        // With the relaunch agent on, only the launchd-managed instance runs; other copies hand off and exit
        if BackgroundRelauncher.handOffIfNeeded() { return }
        if BackgroundRelauncher.applyDefaultIfNeeded() { return }

        // Disable automatic termination so the menu bar status item and global hotkeys remain active indefinitely
        ProcessInfo.processInfo.disableAutomaticTermination("Screenshot utility background runner")

        // Initialize Menu Bar controller
        menuBarController = MenuBarController(
            coordinator: AppCoordinator.shared,
            config: AppConfiguration.shared
        )

        // Configure dock visibility
        updateActivationPolicy(showInDock: AppConfiguration.shared.showDockIcon)

        // Observe dock icon setting changes
        AppConfiguration.shared.$showDockIcon
            .receive(on: DispatchQueue.main)
            .sink { [weak self] showInDock in
                self?.updateActivationPolicy(showInDock: showInDock)
            }
            .store(in: &cancellables)

        // Show Settings on launch, except when launchd silently restores ScreenMint in the background
        let restoreRequestedSettings = BackgroundRelauncher.consumePendingOpenSettings()
        if PermissionsWindowController.isNeeded {
            // Ask for Screen Recording up front rather than on the first shortcut press
            PermissionsWindowController.shared.show()
        } else if !BackgroundRelauncher.isLaunchedByAgent || restoreRequestedSettings {
            AppCoordinator.shared.openSettings()
        }

        // A copy opened from Finder or the Dock asks the background instance to show itself
        DistributedNotificationCenter.default().addObserver(
            forName: BackgroundRelauncher.openSettingsNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in AppCoordinator.shared.openSettings() }
        }

        // Keep the stored preference in sync if the agent was removed in System Settings › Login Items
        if AppConfiguration.shared.relaunchAfterUnexpectedQuit, !BackgroundRelauncher.isAgentEnabled {
            AppConfiguration.shared.relaunchAfterUnexpectedQuit = false
        }

        // Start Global Keyboard Shortcuts
        HotKeyManager.shared.startMonitoring()

        // Start listening for subscription renewals and purchases from other devices
        _ = SubscriptionManager.shared

        // Detect on-device OCR model availability ahead of the first recognition request
        VisionService.shared.prewarm()

        // Mirror the capture history into Spotlight
        SpotlightIndexer.shared.start()
    }

    /// Spotlight result picked: open that capture
    public func application(_ application: NSApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([any NSUserActivityRestoring]) -> Void) -> Bool {
        SpotlightIndexer.open(userActivity)
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    private func updateActivationPolicy(showInDock: Bool) {
        let policy: NSApplication.ActivationPolicy = showInDock ? .regular : .accessory
        NSApp.setActivationPolicy(policy)
        if showInDock {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !CaptureCoordinator.shared.isCapturing else { return true }
        Self.restoreDockIconIfNeeded()
        if !flag && AppConfiguration.shared.showDockIcon {
            AppCoordinator.shared.openSettings()
        }
        return true
    }

    /// Dock › Quit keeps ScreenMint running in the menu bar so global shortcuts keep working.
    /// Quit from the menu bar, logout / shutdown and scripted quits (e.g. Homebrew) still quit.
    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard Self.isQuitFromDock else { return .terminateNow }
        Self.moveToMenuBar()
        return .terminateCancel
    }

    /// Hides the Dock icon and windows while the menu bar item and hotkeys stay active
    public static func moveToMenuBar() {
        AppLogger.shared.app.info("Moving \(AppBranding.appName) to the menu bar instead of quitting.")
        for window in NSApp.windows where window.isVisible && window.styleMask.contains(.titled) && !(window is NSPanel) {
            window.orderOut(nil)
        }
        NSApp.setActivationPolicy(.accessory)
    }

    /// Brings the Dock icon back after `moveToMenuBar()` when the user wants one
    public static func restoreDockIconIfNeeded() {
        guard AppConfiguration.shared.showDockIcon, NSApp.activationPolicy() != .regular else { return }
        NSApp.setActivationPolicy(.regular)
    }

    /// The Dock sends a plain quit Apple Event; logout and shutdown add a quit reason
    private static var isQuitFromDock: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              event.eventClass == AEEventClass(kCoreEventClass),
              event.eventID == AEEventID(kAEQuitApplication),
              event.attributeDescriptor(forKeyword: AEKeyword(kAEQuitReason)) == nil,
              let pid = event.attributeDescriptor(forKeyword: AEKeyword(keySenderPIDAttr))?.int32Value
        else { return false }
        return NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == "com.apple.dock"
    }

    public func applicationWillTerminate(_ notification: Notification) {
        HotKeyManager.shared.stopMonitoring()
        AppLogger.shared.app.info("\(AppBranding.appName) terminating.")
    }
}
