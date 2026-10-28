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
    private var currentMenu: NSMenu?
    /// True while the options menu is open during a recording (right-click)
    private var isShowingMenuWhileRecording = false

    public init(coordinator: AppCoordinator? = nil, config: AppConfiguration? = nil) {
        self.coordinator = coordinator ?? .shared
        self.config = config ?? .shared
        super.init()
        setupStatusItem()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem?.button else { return }

        // App glyph in the menu bar (template, so macOS tints it)
        button.image = AppBranding.menuBarIcon()
        // Used while recording, when the item has no menu: click stops, right-click shows options
        button.target = self
        button.action = #selector(didClickStatusButton(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])

        rebuildMenu()

        // Show/hide the menu bar menu from Settings › General
        config.$showMenuBarIcon
            .receive(on: DispatchQueue.main)
            .sink { [weak self] visible in
                self?.statusItem?.isVisible = visible
            }
            .store(in: &cancellables)

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
        let image = recorder.isActive
            ? NSImage(systemSymbolName: symbol, accessibilityDescription: "Recording")
            : AppBranding.menuBarIcon()
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
        attachMenuForCurrentState()
    }

    /// Normally the item opens the menu. While recording it acts as a stop button instead,
    /// so one click ends the recording without hunting for "Stop Recording" in the menu.
    private func attachMenuForCurrentState() {
        guard !isShowingMenuWhileRecording else { return }
        statusItem?.menu = recorder.isActive ? nil : currentMenu
        statusItem?.button?.toolTip = recorder.isActive ? "Click to stop recording · Right-click for more options" : nil
    }

    @objc private func didClickStatusButton(_ sender: NSStatusBarButton) {
        guard recorder.isActive else { return }
        let event = NSApp.currentEvent
        let wantsMenu = event?.type == .rightMouseUp
            || event?.modifierFlags.contains(.option) == true
            || event?.modifierFlags.contains(.control) == true
        if wantsMenu {
            // Pause / Discard and everything else stay one right-click away
            isShowingMenuWhileRecording = true
            rebuildMenu()
            statusItem?.menu = currentMenu
            sender.performClick(nil) // runs the menu modally
            statusItem?.menu = nil
            isShowingMenuWhileRecording = false
            attachMenuForCurrentState()
        } else {
            recorder.stop()
            rebuildMenu()
        }
    }

    public func rebuildMenu() {
        let settings = config.captureSettings
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        menu.minimumWidth = Self.menuWidth

        // Header: logo, name and where uploads go
        menu.addItem(headerItem())
        menu.addItem(NSMenuItem.separator())

        // 1. Capture Actions
        let regionItem = actionItem("Capture Selected Area", symbol: "crop", action: #selector(didSelectCaptureRegion))
        applyShortcut(settings.shortcutRegion, to: regionItem)
        menu.addItem(regionItem)

        let fullScreenItem = actionItem("Capture Full Screen", symbol: "macwindow", action: #selector(didSelectCaptureFullScreen))
        applyShortcut(settings.shortcutFullScreen, to: fullScreenItem)
        menu.addItem(fullScreenItem)

        let windowItem = actionItem("Capture Window", symbol: "macwindow.on.rectangle", action: #selector(didSelectCaptureWindow))
        applyShortcut(settings.shortcutWindow, to: windowItem)
        menu.addItem(windowItem)

        menu.addItem(NSMenuItem.separator())

        // 2. Screen Recording & OCR
        if recorder.isActive {
            let stopItem = actionItem("Stop Recording (\(RecordingCoordinator.format(recorder.elapsed)))", symbol: "stop.circle.fill", action: #selector(didSelectToggleRecording))
            applyShortcut(settings.shortcutRecording, to: stopItem)
            stopItem.image = stopItem.image?.withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [.systemRed]))
            menu.addItem(stopItem)

            let isPaused = recorder.state == .paused
            menu.addItem(actionItem(isPaused ? "Resume Recording" : "Pause Recording", symbol: isPaused ? "play.circle" : "pause.circle", action: #selector(didSelectPauseRecording)))
            menu.addItem(actionItem("Discard Recording", symbol: "trash", action: #selector(didSelectDiscardRecording)))
        } else {
            let recordMenu = NSMenu()
            let recordRegion = actionItem("Selected Area", symbol: "crop", action: #selector(didSelectRecordRegion))
            applyShortcut(settings.shortcutRecording, to: recordRegion)
            let recordWindow = actionItem("Window", symbol: "macwindow.on.rectangle", action: #selector(didSelectRecordWindow))
            let recordScreen = actionItem("Full Screen", symbol: "macwindow", action: #selector(didSelectRecordFullScreen))
            for item in [recordRegion, recordWindow, recordScreen] {
                item.isEnabled = recorder.state == .idle
                recordMenu.addItem(item)
            }
            let recordingItem = actionItem("Record Screen", symbol: "record.circle", action: nil)
            recordingItem.submenu = recordMenu
            menu.addItem(recordingItem)
        }

        let ocrItem = actionItem("OCR Text from Screen", symbol: "text.viewfinder", action: #selector(didSelectOcr))
        applyShortcut(settings.shortcutQuickOcr, to: ocrItem)
        menu.addItem(ocrItem)

        menu.addItem(NSMenuItem.separator())

        // 3. Recent Captures & Library
        let recentMenu = NSMenu()
        if coordinator.recentAssets.isEmpty {
            let emptyItem = NSMenuItem(title: "No recent captures", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            recentMenu.addItem(emptyItem)
        } else {
            for asset in coordinator.recentAssets.prefix(5) {
                let item = actionItem(asset.title, symbol: asset.mediaType.systemIconName, action: #selector(didSelectOpenRecentAsset(_:)))
                item.representedObject = asset
                if #available(macOS 14.4, *) {
                    item.subtitle = Self.relativeDate.localizedString(for: asset.createdAt, relativeTo: Date())
                }
                recentMenu.addItem(item)
            }
        }
        let recentSubmenuItem = actionItem("Recent Captures", symbol: "clock.arrow.circlepath", action: nil)
        recentSubmenuItem.submenu = recentMenu
        menu.addItem(recentSubmenuItem)

        menu.addItem(actionItem("Open Library…", symbol: "photo.stack", action: #selector(didSelectLibrary)))

        menu.addItem(NSMenuItem.separator())

        // 4. Settings, Support & App Management
        let settingsItem = actionItem("Settings…", symbol: "gearshape", action: #selector(didSelectSettings))
        settingsItem.keyEquivalent = ","
        settingsItem.keyEquivalentModifierMask = [.command]
        menu.addItem(settingsItem)

        let proTitle = SubscriptionManager.shared.isPro ? "SyncShot Pro" : "Upgrade to Pro…"
        menu.addItem(actionItem(proTitle, symbol: "crown", action: #selector(didSelectPro)))

        let helpMenu = NSMenu()
        helpMenu.addItem(actionItem("Contact Support…", symbol: "questionmark.bubble", action: #selector(didSelectSupport)))
        helpMenu.addItem(actionItem("Privacy Policy", symbol: "hand.raised", action: #selector(didSelectPrivacyPolicy)))
        helpMenu.addItem(actionItem("Terms of Use", symbol: "doc.text", action: #selector(didSelectTerms)))
        let helpItem = actionItem("Help & Support", symbol: "questionmark.circle", action: nil)
        helpItem.submenu = helpMenu
        menu.addItem(helpItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = actionItem("Quit SyncShot", symbol: "power", action: #selector(didSelectQuit))
        quitItem.keyEquivalent = "q"
        quitItem.keyEquivalentModifierMask = [.command]
        menu.addItem(quitItem)

        currentMenu = menu
        attachMenuForCurrentState()
    }

    // MARK: - Menu Building Helpers

    private static let menuWidth: CGFloat = 236
    private static let relativeDate: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    /// Standard row: consistent symbol size and weight so every item lines up
    private func actionItem(_ title: String, symbol: String, action: Selector?) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .regular))
        item.target = action == nil ? nil : self
        return item
    }

    private func headerItem() -> NSMenuItem {
        let header = MenuHeaderView(
            destination: config.storageMode == .localOnly ? "Local" : config.storageMode.title,
            destinationSymbol: config.storageMode.iconName
        )
        let host = NSHostingView(rootView: header)
        host.frame = NSRect(x: 0, y: 0, width: Self.menuWidth, height: host.fittingSize.height)
        let item = NSMenuItem()
        item.view = host
        item.isEnabled = false
        return item
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
            NSWorkspace.shared.open(asset.originalFileURL)
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

    @objc private func didSelectSupport() {
        AppBranding.contactSupport()
    }

    @objc private func didSelectPro() {
        coordinator.openSettings(tab: .subscription)
    }

    @objc private func didSelectPrivacyPolicy() {
        AppBranding.openPrivacyPolicy()
    }

    @objc private func didSelectTerms() {
        AppBranding.openTermsOfUse()
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

// MARK: - Header

/// Compact one-line menu header: logo, name and the upload destination
private struct MenuHeaderView: View {
    let destination: String
    let destinationSymbol: String

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: AppBranding.logo(size: 22))
                .resizable()
                .interpolation(.high)
                .frame(width: 22, height: 22)
            Text(AppBranding.appName)
                .font(.system(size: 13, weight: .semibold))
            Spacer(minLength: 8)
            Label(destination, systemImage: destinationSymbol)
                .labelStyle(.titleAndIcon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Color.primary.opacity(0.07), in: Capsule())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
    }
}
