import AppKit
import SwiftUI
import Combine

private let keyAELaunchedAsLogInItem: OSType = 0x6c676974 // 'lgit'
private let keyAELaunchedAsServiceItem: OSType = 0x73766974 // 'svit'

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

        // Configure dock visibility quietly on launch
        updateActivationPolicy(showInDock: AppConfiguration.shared.showDockIcon, activate: false)

        // Observe dock icon setting changes (when user toggles in Settings)
        AppConfiguration.shared.$showDockIcon
            .receive(on: DispatchQueue.main)
            .sink { [weak self] showInDock in
                self?.updateActivationPolicy(showInDock: showInDock, activate: true)
            }
            .store(in: &cancellables)

        // Handle window presentation on launch:
        // When launched at system boot / login, run completely silently in the menu bar without opening windows.
        let restoreRequestedSettings = BackgroundRelauncher.consumePendingOpenSettings()
        let launchedAtLogin = isLaunchedAtLogin

        if restoreRequestedSettings {
            AppCoordinator.shared.openSettings()
        } else if launchedAtLogin {
            AppLogger.shared.app.info("\(AppBranding.appName) launched at login; running silently in menu bar.")
        } else if PermissionsWindowController.isNeeded {
            // Ask for Screen Recording up front on manual first launch
            PermissionsWindowController.shared.show()
        } else {
            // Manual launch: open Settings so the user can configure preferences and view shortcuts
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

    private func updateActivationPolicy(showInDock: Bool, activate: Bool = false) {
        let policy: NSApplication.ActivationPolicy = showInDock ? .regular : .accessory
        NSApp.setActivationPolicy(policy)
        if showInDock && activate {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !CaptureCoordinator.shared.isCapturing else { return true }
        Self.restoreDockIconIfNeeded()
        if !flag {
            AppCoordinator.shared.openSettings()
        }
        return true
    }

    /// Determines whether this process was launched automatically at login / system boot
    private var isLaunchedAtLogin: Bool {
        // 1. Started by launchd relaunch agent
        if BackgroundRelauncher.isLaunchedByAgent {
            return true
        }

        // 2. Official macOS AppleEvent attributes for login items
        if let event = NSAppleEventManager.shared().currentAppleEvent {
            if event.attributeDescriptor(forKeyword: AEKeyword(keyAELaunchedAsLogInItem)) != nil
                || event.attributeDescriptor(forKeyword: AEKeyword(keyAELaunchedAsServiceItem)) != nil {
                return true
            }
        }

        // 3. Process arguments
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--login-item") || args.contains("-background") || args.contains("--background") {
            return true
        }

        // 4. System startup heuristic: launchAtLogin is enabled and system uptime is under 3 minutes
        if AppConfiguration.shared.launchAtLogin && ProcessInfo.processInfo.systemUptime < 180 {
            return true
        }

        return false
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
