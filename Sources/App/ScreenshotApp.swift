import SwiftUI

/// Main application entry point for ScreenshotApp
@main
struct ScreenshotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var config = AppConfiguration.shared
    @StateObject private var coordinator = AppCoordinator.shared

    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(config)
                .environmentObject(coordinator)
        }
        .commands { AppCommands() }
    }
}
