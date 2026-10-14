import AppKit
import SwiftUI
import Combine

/// AppKit application delegate handling lifecycle, menu bar instantiation, and dock visibility.
@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?
    private var cancellables = Set<AnyCancellable>()

    public func applicationDidFinishLaunching(_ notification: Notification) {
        AppLogger.shared.app.info("ScreenshotApp launched successfully.")

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
        AppLogger.shared.app.info("ScreenshotApp terminating.")
    }
}
