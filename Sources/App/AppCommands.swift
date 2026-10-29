import SwiftUI

/// Main menu bar sections (ScreenMint · File · Edit · Capture · View · Window · Help) shown while ScreenMint is the active app.
/// Global capture shortcuts are owned by `HotKeyManager`, so they are not repeated here as key equivalents.
struct AppCommands: Commands {
    var body: some Commands {
        // ScreenMint menu: route About and Settings to the app's own Settings window
        CommandGroup(replacing: .appInfo) {
            Button("About \(AppBranding.appName)") { AppCoordinator.shared.openSettings(tab: .about) }
        }
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { AppCoordinator.shared.openSettings() }
                .keyboardShortcut(",", modifiers: .command)
            Button("\(AppBranding.appName) Pro…") { AppCoordinator.shared.openSettings(tab: .subscription) }
        }

        // File
        CommandGroup(replacing: .newItem) {
            Button("Open Library…") { AppCoordinator.shared.openLibrary() }
                .keyboardShortcut("l", modifiers: [.command, .shift])
        }

        // Capture
        CommandMenu("Capture") {
            CaptureMenuContent()
        }

        // View
        CommandGroup(before: .toolbar) {
            Button("Storage & Cloud…") { AppCoordinator.shared.openSettings(tab: .storage) }
            Button("Keyboard Shortcuts…") { AppCoordinator.shared.openSettings(tab: .shortcuts) }
            Button("Diagnostics…") { AppCoordinator.shared.openSettings(tab: .diagnostics) }
            Divider()
        }

        // Help
        CommandGroup(replacing: .help) {
            Button("Contact Support…") { AppBranding.contactSupport() }
            Button("Privacy Policy") { AppBranding.openPrivacyPolicy() }
            Button("Terms of Use") { AppBranding.openTermsOfUse() }
            Divider()
            Button("Screen Recording Permission…") { AppCoordinator.shared.openSettings(tab: .privacy) }
        }
    }
}

/// Capture menu items; observes the recorder so Stop / Pause appear while recording
private struct CaptureMenuContent: View {
    @ObservedObject private var recorder = RecordingCoordinator.shared
    private let coordinator = AppCoordinator.shared

    var body: some View {
        Button("Capture Selected Area") { coordinator.triggerCapture(type: .region) }
        Button("Capture Full Screen") { coordinator.triggerCapture(type: .fullScreen) }
        Button("Capture All Screens") { coordinator.triggerCapture(type: .allScreens) }
        Button("Capture Window") { coordinator.triggerCapture(type: .window) }

        Divider()

        if recorder.isActive {
            Button("Stop Recording") { coordinator.triggerCapture(type: .recording) }
            Button(recorder.state == .paused ? "Resume Recording" : "Pause Recording") { recorder.togglePause() }
            Button("Discard Recording") { recorder.cancel() }
        } else {
            Menu("Record Screen") {
                Button("Selected Area") { coordinator.startRecording(.region) }
                Button("Window") { coordinator.startRecording(.window) }
                Button("Full Screen") { coordinator.startRecording(.fullScreen) }
            }
            .disabled(recorder.state != .idle)
        }

        Button("OCR Text from Screen") { coordinator.triggerCapture(type: .ocr) }
    }
}
