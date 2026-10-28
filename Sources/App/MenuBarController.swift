import AppKit
import Combine
import SwiftUI

/// AppKit NSStatusItem menu-bar controller providing native menu bar dropdown.
@MainActor
public final class MenuBarController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private let coordinator: AppCoordinator
    private let config: AppConfiguration
    private let recorder = RecordingCoordinator.shared
    private var cancellables = Set<AnyCancellable>()

    public init(coordinator: AppCoordinator? = nil, config: AppConfiguration? = nil) {
        self.coordinator = coordinator ?? .shared
        self.config = config ?? .shared
        super.init()
        setupStatusItem()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem?.button else { return }

        // Configure system image for status bar
        if let image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "SyncShot") {
            image.isTemplate = true
            button.image = image
        }

        rebuildMenu()

        // Live recording indicator: red dot + elapsed time in the menu bar
        recorder.$state.combineLatest(recorder.$elapsed)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state, elapsed in
                self?.updateStatusButton(state: state, elapsed: elapsed)
            }
            .store(in: &cancellables)
    }

    private func updateStatusButton(state: RecordingCoordinator.State, elapsed: TimeInterval) {
        guard let button = statusItem?.button else { return }
        let symbol: String
        switch state {
        case .recording: symbol = "record.circle.fill"
        case .paused: symbol = "pause.circle.fill"
        case .finishing: symbol = "hourglass"
        default: symbol = "camera.viewfinder"
        }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: recorder.isActive ? "Recording" : "SyncShot")
        if recorder.isActive {
            let color: NSColor = state == .paused ? .systemYellow : .systemRed
            button.image = image?.withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [color]))
            button.image?.isTemplate = false
            button.title = " " + RecordingCoordinator.format(elapsed)
            button.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .medium)
            button.imagePosition = .imageLeading
        } else {
            image?.isTemplate = true
            button.image = image
            button.title = ""
            button.imagePosition = .imageOnly
        }
    }

    public func rebuildMenu() {
        let settings = config.captureSettings
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false

        // 1. Capture Actions
        let regionItem = NSMenuItem(
            title: "Capture Selected Area",
            action: #selector(didSelectCaptureRegion),
            keyEquivalent: ""
        )
        applyShortcut(settings.shortcutRegion, to: regionItem)
        regionItem.image = NSImage(systemSymbolName: "crop", accessibilityDescription: nil)
        regionItem.target = self
        menu.addItem(regionItem)

        let fullScreenItem = NSMenuItem(
            title: "Capture Full Screen",
            action: #selector(didSelectCaptureFullScreen),
            keyEquivalent: ""
        )
        applyShortcut(settings.shortcutFullScreen, to: fullScreenItem)
        fullScreenItem.image = NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil)
        fullScreenItem.target = self
        menu.addItem(fullScreenItem)

        let windowItem = NSMenuItem(
            title: "Capture Window",
            action: #selector(didSelectCaptureWindow),
            keyEquivalent: ""
        )
        applyShortcut(settings.shortcutWindow, to: windowItem)
        windowItem.image = NSImage(systemSymbolName: "macwindow.on.rectangle", accessibilityDescription: nil)
        windowItem.target = self
        menu.addItem(windowItem)

        menu.addItem(NSMenuItem.separator())

        // 2. Screen Recording & OCR
        if recorder.isActive {
            let stopItem = NSMenuItem(title: "Stop Recording (\(RecordingCoordinator.format(recorder.elapsed)))", action: #selector(didSelectToggleRecording), keyEquivalent: "")
            applyShortcut(settings.shortcutRecording, to: stopItem)
            stopItem.image = NSImage(systemSymbolName: "stop.circle.fill", accessibilityDescription: nil)
            stopItem.target = self
            menu.addItem(stopItem)

            let pauseItem = NSMenuItem(title: recorder.state == .paused ? "Resume Recording" : "Pause Recording", action: #selector(didSelectPauseRecording), keyEquivalent: "")
            pauseItem.image = NSImage(systemSymbolName: recorder.state == .paused ? "play.circle" : "pause.circle", accessibilityDescription: nil)
            pauseItem.target = self
            menu.addItem(pauseItem)

            let discardItem = NSMenuItem(title: "Discard Recording", action: #selector(didSelectDiscardRecording), keyEquivalent: "")
            discardItem.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
            discardItem.target = self
            menu.addItem(discardItem)
        } else {
            let recordMenu = NSMenu()
            let recordRegion = NSMenuItem(title: "Selected Area", action: #selector(didSelectRecordRegion), keyEquivalent: "")
            applyShortcut(settings.shortcutRecording, to: recordRegion)
            recordRegion.image = NSImage(systemSymbolName: "crop", accessibilityDescription: nil)
            let recordWindow = NSMenuItem(title: "Window", action: #selector(didSelectRecordWindow), keyEquivalent: "")
            recordWindow.image = NSImage(systemSymbolName: "macwindow.on.rectangle", accessibilityDescription: nil)
            let recordScreen = NSMenuItem(title: "Full Screen", action: #selector(didSelectRecordFullScreen), keyEquivalent: "")
            recordScreen.image = NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil)
            for item in [recordRegion, recordWindow, recordScreen] {
                item.target = self
                item.isEnabled = recorder.state == .idle
                recordMenu.addItem(item)
            }
            let recordingItem = NSMenuItem(title: "Record Screen", action: nil, keyEquivalent: "")
            recordingItem.image = NSImage(systemSymbolName: "record.circle", accessibilityDescription: nil)
            recordingItem.submenu = recordMenu
            menu.addItem(recordingItem)
        }

        let ocrItem = NSMenuItem(
            title: "OCR Text from Screen",
            action: #selector(didSelectOcr),
            keyEquivalent: ""
        )
        applyShortcut(settings.shortcutQuickOcr, to: ocrItem)
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
        if let latest = coordinator.recentAssets.first {
            let editLatest = NSMenuItem(title: "Annotate Last Capture", action: #selector(didSelectOpenRecentAsset(_:)), keyEquivalent: "")
            editLatest.target = self
            editLatest.representedObject = latest
            editLatest.image = NSImage(systemSymbolName: "pencil.and.outline", accessibilityDescription: nil)
            menu.addItem(editLatest)
        }

        let recentSubmenuItem = NSMenuItem(title: "Recent Captures", action: nil, keyEquivalent: "")
        recentSubmenuItem.submenu = recentMenu
        menu.addItem(recentSubmenuItem)

        let libraryItem = NSMenuItem(title: "Open Library…", action: #selector(didSelectLibrary), keyEquivalent: "")
        libraryItem.image = NSImage(systemSymbolName: "photo.stack", accessibilityDescription: nil)
        libraryItem.target = self
        menu.addItem(libraryItem)

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
            title: "Quit SyncShot",
            action: #selector(didSelectQuit),
            keyEquivalent: "q"
        )
        quitItem.keyEquivalentModifierMask = [.command]
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    /// Mirrors the user's configured global shortcut on a menu item (display only; Carbon handles the hotkey)
    private func applyShortcut(_ binding: ShortcutBinding, to item: NSMenuItem) {
        guard binding.isValidGlobalHotKey, let code = binding.keyCode, let name = KeyCodeMap.name(for: code), name.count == 1 else { return }
        item.keyEquivalent = name.lowercased()
        var mask: NSEvent.ModifierFlags = []
        if binding.modifiers.contains("⌘") { mask.insert(.command) }
        if binding.modifiers.contains("⇧") { mask.insert(.shift) }
        if binding.modifiers.contains("⌥") { mask.insert(.option) }
        if binding.modifiers.contains("⌃") { mask.insert(.control) }
        item.keyEquivalentModifierMask = mask
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

    @objc private func didSelectPauseRecording() {
        recorder.togglePause()
    }

    @objc private func didSelectDiscardRecording() {
        recorder.cancel()
    }

    @objc private func didSelectRecordRegion() {
        coordinator.startRecording(.region)
    }

    @objc private func didSelectRecordWindow() {
        coordinator.startRecording(.window)
    }

    @objc private func didSelectRecordFullScreen() {
        coordinator.startRecording(.fullScreen)
    }

    @objc private func didSelectOcr() {
        coordinator.triggerCapture(type: .ocr)
    }

    @objc private func didSelectOpenRecentAsset(_ sender: NSMenuItem) {
        guard let asset = sender.representedObject as? ScreenshotAsset else { return }
        if FileManager.default.fileExists(atPath: asset.originalFileURL.path) {
            coordinator.openEditor(for: asset)
        } else {
            CaptureHUD.shared.show(title: "Capture file not found", detail: asset.originalFileURL.lastPathComponent, symbol: "exclamationmark.triangle.fill")
        }
    }

    @objc private func didSelectLibrary() {
        coordinator.openLibrary()
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
