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

        // 1. Capture
        let regionItem = actionItem("Capture Area", symbol: "crop", action: #selector(didSelectCaptureRegion))
        applyShortcut(settings.shortcutRegion, to: regionItem)
        menu.addItem(regionItem)

        let fullScreenItem = actionItem("Capture Screen", symbol: "macwindow", action: #selector(didSelectCaptureFullScreen))
        applyShortcut(settings.shortcutFullScreen, to: fullScreenItem)
        menu.addItem(fullScreenItem)

        let windowItem = actionItem("Capture Window", symbol: "macwindow.on.rectangle", action: #selector(didSelectCaptureWindow))
        applyShortcut(settings.shortcutWindow, to: windowItem)
        menu.addItem(windowItem)

        let ocrItem = actionItem("Capture Text", symbol: "text.viewfinder", action: #selector(didSelectOcr))
        applyShortcut(settings.shortcutQuickOcr, to: ocrItem)
        menu.addItem(ocrItem)

        // 2. Recording
        if recorder.isActive {
            let stopItem = actionItem("Stop Recording (\(RecordingCoordinator.format(recorder.elapsed)))", symbol: "stop.fill", action: #selector(didSelectToggleRecording), tint: .systemRed)
            applyShortcut(settings.shortcutRecording, to: stopItem)
            menu.addItem(stopItem)

            let isPaused = recorder.state == .paused
            menu.addItem(actionItem(isPaused ? "Resume Recording" : "Pause Recording", symbol: isPaused ? "play.fill" : "pause.fill", action: #selector(didSelectPauseRecording)))
            menu.addItem(actionItem("Discard Recording", symbol: "trash", action: #selector(didSelectDiscardRecording)))
        } else {
            let recordMenu = NSMenu()
            let recordRegion = actionItem("Area", symbol: "crop", action: #selector(didSelectRecordRegion))
            applyShortcut(settings.shortcutRecording, to: recordRegion)
            let recordWindow = actionItem("Window", symbol: "macwindow.on.rectangle", action: #selector(didSelectRecordWindow))
            let recordScreen = actionItem("Screen", symbol: "macwindow", action: #selector(didSelectRecordFullScreen))
            for item in [recordRegion, recordWindow, recordScreen] {
                item.isEnabled = recorder.state == .idle
                recordMenu.addItem(item)
            }
            let recordingItem = actionItem("Record Screen", symbol: "record.circle", action: nil, tint: .systemRed)
            recordingItem.submenu = recordMenu
            menu.addItem(recordingItem)
        }

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

        let libraryItem = actionItem("Open Library…", symbol: "photo.on.rectangle.angled", action: #selector(didSelectLibrary))
        libraryItem.keyEquivalent = "l"
        libraryItem.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(libraryItem)

        menu.addItem(NSMenuItem.separator())

        // 4. Footer bar: Settings · Pro · Support · Quit in one row instead of four
        menu.addItem(footerItem(for: menu))

        // Keep ⌘, and ⌘Q working while the footer replaces their rows
        for (title, key, action) in [("Settings…", ",", #selector(didSelectSettings)), ("Quit \(AppBranding.appName)", "q", #selector(didSelectQuit))] {
            let hidden = NSMenuItem(title: title, action: action, keyEquivalent: key)
            hidden.keyEquivalentModifierMask = [.command]
            hidden.target = self
            hidden.isHidden = true
            hidden.allowsKeyEquivalentWhenHidden = true
            menu.addItem(hidden)
        }

        currentMenu = menu
        attachMenuForCurrentState()
    }

    // MARK: - Menu Building Helpers

    private static let menuWidth: CGFloat = 260
    private static let relativeDate: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    /// Standard row: the symbol sits on a soft rounded tile with even padding, so every row lines up
    private func actionItem(_ title: String, symbol: String, action: Selector?, tint: NSColor? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.image = Self.tileImage(symbol: symbol, tint: tint)
        item.target = action == nil ? nil : self
        return item
    }

    /// 20 pt tile with a 12 pt symbol; drawn lazily so it follows light / dark appearance
    private static func tileImage(symbol: String, tint: NSColor?) -> NSImage? {
        guard let glyph = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11.5, weight: .medium)) else { return nil }
        let size = NSSize(width: 20, height: 20)
        return NSImage(size: size, flipped: false) { rect in
            let tile = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 5.5, yRadius: 5.5)
            (tint?.withAlphaComponent(0.16) ?? NSColor.labelColor.withAlphaComponent(0.08)).setFill()
            tile.fill()

            // Tint the template symbol by filling through it
            let symbolColor = tint ?? NSColor.labelColor.withAlphaComponent(0.85)
            let glyphSize = glyph.size
            let glyphRect = NSRect(
                x: rect.midX - glyphSize.width / 2, y: rect.midY - glyphSize.height / 2,
                width: glyphSize.width, height: glyphSize.height
            )
            let tinted = NSImage(size: glyphSize, flipped: false) { inner in
                glyph.draw(in: inner)
                symbolColor.set()
                inner.fill(using: .sourceAtop)
                return true
            }
            tinted.draw(in: glyphRect)
            return true
        }
    }

    private func headerItem() -> NSMenuItem {
        let header = MenuHeaderView(
            destination: config.storageMode == .localOnly ? "Local" : config.storageMode.title,
            destinationSymbol: config.storageMode.iconName,
            isPro: SubscriptionManager.shared.isPro
        )
        return hostedItem(header)
    }

    private func footerItem(for menu: NSMenu) -> NSMenuItem {
        let perform: (Selector) -> Void = { [weak self, weak menu] selector in
            menu?.cancelTracking()
            // Run after the menu has closed so windows can come to the front
            DispatchQueue.main.async { _ = self?.perform(selector) }
        }
        let footer = MenuFooterView(
            isPro: SubscriptionManager.shared.isPro,
            onSettings: { perform(#selector(MenuBarController.didSelectSettings)) },
            onPro: { perform(#selector(MenuBarController.didSelectPro)) },
            onSupport: { perform(#selector(MenuBarController.didSelectSupport)) },
            onQuit: { perform(#selector(MenuBarController.didSelectQuit)) }
        )
        return hostedItem(footer)
    }

    private func hostedItem<Content: View>(_ view: Content) -> NSMenuItem {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: Self.menuWidth, height: host.fittingSize.height)
        let item = NSMenuItem()
        item.view = host
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
    let isPro: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: AppBranding.logo(size: 26))
                .resizable()
                .interpolation(.high)
                .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 5) {
                    Text(AppBranding.appName)
                        .font(.system(size: 13, weight: .semibold))
                    if isPro {
                        Text("PRO")
                            .font(.system(size: 8.5, weight: .heavy))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1.5)
                            .foregroundStyle(.white)
                            .background(Color.orange.gradient, in: Capsule())
                    }
                }
                Text("by \(AppBranding.developerName)")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Label(destination, systemImage: destinationSymbol)
                .labelStyle(.titleAndIcon)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.primary.opacity(0.07), in: Capsule())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Footer

/// One row of equal-width icon buttons replacing the Settings / Pro / Support / Quit rows
private struct MenuFooterView: View {
    let isPro: Bool
    let onSettings: () -> Void
    let onPro: () -> Void
    let onSupport: () -> Void
    let onQuit: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            MenuFooterButton(symbol: "gearshape", title: "Settings", help: "Settings (⌘,)", action: onSettings)
            MenuFooterButton(symbol: "crown", title: isPro ? "Pro" : "Upgrade", help: isPro ? "\(AppBranding.appName) Pro" : "Upgrade to Pro", tint: .orange, action: onPro)
            MenuFooterButton(symbol: "envelope", title: "Support", help: "Email \(AppBranding.developerName)", action: onSupport)
            MenuFooterButton(symbol: "power", title: "Quit", help: "Quit \(AppBranding.appName) (⌘Q)", action: onQuit)
        }
        .padding(.horizontal, 10)
        .padding(.top, 2)
        .padding(.bottom, 4)
    }
}

private struct MenuFooterButton: View {
    let symbol: String
    let title: String
    let help: String
    var tint: Color?
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(tint ?? .primary)
                    .frame(width: 30, height: 24)
                    .background((tint ?? .primary).opacity(isHovered ? 0.18 : 0.08), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}
