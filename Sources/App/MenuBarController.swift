import AppKit
import SwiftUI

/// AppKit NSStatusItem menu-bar controller providing native menu bar dropdown.
@MainActor
public final class MenuBarController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private let coordinator: AppCoordinator
    private let config: AppConfiguration

    public init(coordinator: AppCoordinator = .shared, config: AppConfiguration = .shared) {
        self.coordinator = coordinator
        self.config = config
        super.init()
        setupStatusItem()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem?.button else { return }

        // Configure system image for status bar
        if let image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "ScreenshotApp") {
            image.isTemplate = true
            button.image = image
        }

        rebuildMenu()
    }

    public func rebuildMenu() {
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false

        // 1. Capture Actions
        let regionItem = NSMenuItem(
            title: "Capture Selected Area",
            action: #selector(didSelectCaptureRegion),
            keyEquivalent: "4"
        )
        regionItem.keyEquivalentModifierMask = [.command, .shift]
        regionItem.image = NSImage(systemSymbolName: "crop", accessibilityDescription: nil)
        regionItem.target = self
        menu.addItem(regionItem)

        let fullScreenItem = NSMenuItem(
            title: "Capture Full Screen",
            action: #selector(didSelectCaptureFullScreen),
            keyEquivalent: "3"
        )
        fullScreenItem.keyEquivalentModifierMask = [.command, .shift]
        fullScreenItem.image = NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil)
        fullScreenItem.target = self
        menu.addItem(fullScreenItem)

        let windowItem = NSMenuItem(
            title: "Capture Window",
            action: #selector(didSelectCaptureWindow),
            keyEquivalent: "5"
        )
        windowItem.keyEquivalentModifierMask = [.command, .shift]
        windowItem.image = NSImage(systemSymbolName: "macwindow.on.rectangle", accessibilityDescription: nil)
        windowItem.target = self
        menu.addItem(windowItem)

        menu.addItem(NSMenuItem.separator())

        // 2. Screen Recording & OCR
        let recordTitle = coordinator.isRecordingActive ? "Stop Screen Recording" : "Record Screen..."
        let recordingItem = NSMenuItem(
            title: recordTitle,
            action: #selector(didSelectToggleRecording),
            keyEquivalent: "6"
        )
        recordingItem.keyEquivalentModifierMask = [.command, .shift]
        recordingItem.image = NSImage(systemSymbolName: coordinator.isRecordingActive ? "stop.circle.fill" : "record.circle", accessibilityDescription: nil)
        recordingItem.target = self
        menu.addItem(recordingItem)

        let ocrItem = NSMenuItem(
            title: "OCR Text from Screen",
            action: #selector(didSelectOcr),
            keyEquivalent: "7"
        )
        ocrItem.keyEquivalentModifierMask = [.command, .shift]
        ocrItem.image = NSImage(systemSymbolName: "text.viewfinder", accessibilityDescription: nil)
        ocrItem.target = self
        menu.addItem(ocrItem)

        menu.addItem(NSMenuItem.separator())

        // 3. Storage Destination Display
        let storageStatusItem = NSMenuItem(
            title: "Destination: \(config.storageMode.title)",
            action: nil,
            keyEquivalent: ""
        )
        storageStatusItem.isEnabled = false
        storageStatusItem.image = NSImage(systemSymbolName: config.storageMode.iconName, accessibilityDescription: nil)
        menu.addItem(storageStatusItem)

        // 4. Recent Captures Submenu
        let recentMenu = NSMenu()
        if coordinator.recentAssets.isEmpty {
            let emptyItem = NSMenuItem(title: "No recent captures", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            recentMenu.addItem(emptyItem)
        } else {
            for asset in coordinator.recentAssets.prefix(5) {
                let item = NSMenuItem(title: asset.title, action: #selector(didSelectOpenRecentAsset(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = asset
                item.image = NSImage(systemSymbolName: asset.mediaType.systemIconName, accessibilityDescription: nil)
                recentMenu.addItem(item)
            }
        }
        let recentSubmenuItem = NSMenuItem(title: "Recent Captures", action: nil, keyEquivalent: "")
        recentSubmenuItem.submenu = recentMenu
        menu.addItem(recentSubmenuItem)

        menu.addItem(NSMenuItem.separator())

        // 5. Settings & App Management
        let settingsItem = NSMenuItem(
            title: "Settings...",
            action: #selector(didSelectSettings),
            keyEquivalent: ","
        )
        settingsItem.keyEquivalentModifierMask = [.command]
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: "Quit ScreenshotApp",
            action: #selector(didSelectQuit),
            keyEquivalent: "q"
        )
        quitItem.keyEquivalentModifierMask = [.command]
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    // MARK: - Menu Actions

    @objc private func didSelectCaptureRegion() {
        coordinator.triggerCapture(type: .region)
    }

    @objc private func didSelectCaptureFullScreen() {
        coordinator.triggerCapture(type: .fullScreen)
    }

    @objc private func didSelectCaptureWindow() {
        coordinator.triggerCapture(type: .window)
    }

    @objc private func didSelectToggleRecording() {
        coordinator.triggerCapture(type: .recording)
        rebuildMenu()
    }

    @objc private func didSelectOcr() {
        coordinator.triggerCapture(type: .ocr)
    }

    @objc private func didSelectOpenRecentAsset(_ sender: NSMenuItem) {
        if let asset = sender.representedObject as? ScreenshotAsset {
            NSWorkspace.shared.open(asset.originalFileURL)
        }
    }

    @objc private func didSelectSettings() {
        coordinator.openSettings()
    }

    @objc private func didSelectQuit() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - NSMenuDelegate

    public func menuWillOpen(_ menu: NSMenu) {
        // Refresh items dynamically before opening
        rebuildMenu()
    }
}
