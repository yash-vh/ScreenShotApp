import AppKit
import SwiftUI
import Combine

/// AppKit application delegate handling lifecycle, menu bar instantiation, and dock visibility.
@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?
    private var cancellables = Set<AnyCancellable>()

    public func applicationDidFinishLaunching(_ notification: Notification) {
        AppLogger.shared.app.info("SyncShot launched successfully.")

        // With the relaunch agent on, only the launchd-managed instance runs; other copies hand off and exit
        if BackgroundRelauncher.handOffIfNeeded() { return }

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

        // Show Settings on launch, except when launchd silently restores SyncShot in the background
        let restoreRequestedSettings = BackgroundRelauncher.consumePendingOpenSettings()
        if !BackgroundRelauncher.isLaunchedByAgent || restoreRequestedSettings {
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
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    private func updateActivationPolicy(showInDock: Bool) {
        let policy: NSApplication.ActivationPolicy = showInDock ? .regular : .accessory
        NSApp.setActivationPolicy(policy)
    }

    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            AppCoordinator.shared.openSettings()
        }
        return true
    }

    public func applicationWillTerminate(_ notification: Notification) {
        HotKeyManager.shared.stopMonitoring()
        AppLogger.shared.app.info("SyncShot terminating.")
    }
}
