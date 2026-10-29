import AppKit
import Carbon
import Combine

// Global C-function pointer for Carbon event callback
private func carbonHotKeyEventHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ theEvent: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event = theEvent else { return noErr }
    var hotKeyID = EventHotKeyID()
    let err = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    if err == noErr {
        DispatchQueue.main.async {
            HotKeyManager.shared.handleHotKeyTriggered(id: hotKeyID.id)
        }
    }
    return noErr
}

/// System-wide hotkey manager built on Carbon `RegisterEventHotKey`.
///
/// Hotkeys are registered from the user's bindings in `CaptureSettings` (including custom capture
/// shortcuts) and re-registered whenever those settings change. Works from any application without
/// Accessibility permission. macOS's own screenshot shortcuts (⇧⌘3/4/5/6) are never registered,
/// so the built-in screenshot tool keeps working alongside YnShot.
@MainActor
public final class HotKeyManager: ObservableObject {
    public static let shared = HotKeyManager()

    private static let signature = OSType(0x534E4150) // 'SNAP'

    private var eventHandlerRef: EventHandlerRef?
    private var registeredHotKeyRefs: [EventHotKeyRef] = []
    private var actionsByID: [UInt32: CaptureActionType] = [:]
    private var settingsObserver: AnyCancellable?
    private var isSuspended = false

    /// Bindings that failed to register (usually taken by macOS or another app), keyed by display string
    @Published public private(set) var failedBindings: [String] = []

    private init() {}

    // MARK: - Lifecycle

    public func startMonitoring() {
        stopMonitoring()
        installCarbonEventHandler()
        registerHotKeys(from: AppConfiguration.shared.captureSettings)

        settingsObserver = AppConfiguration.shared.$captureSettings
            .map(Self.hotKeySignature)
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self, !self.isSuspended else { return }
                self.registerHotKeys(from: AppConfiguration.shared.captureSettings)
            }

        AppLogger.shared.capture.info("Global keyboard shortcuts registered (\(self.registeredHotKeyRefs.count) hotkeys).")
    }

    public func stopMonitoring() {
        settingsObserver = nil
        unregisterHotKeys()
        if let handler = eventHandlerRef {
            RemoveEventHandler(handler)
            eventHandlerRef = nil
        }
    }

    /// Temporarily releases all hotkeys (e.g. while the user records a new shortcut in Settings)
    public func suspend() {
        guard !isSuspended else { return }
        isSuspended = true
        unregisterHotKeys()
    }

    public func resume() {
        guard isSuspended else { return }
        isSuspended = false
        registerHotKeys(from: AppConfiguration.shared.captureSettings)
    }

    // MARK: - Registration

    private func installCarbonEventHandler() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), carbonHotKeyEventHandler, 1, &eventType, nil, &eventHandlerRef)
    }

    /// Everything that affects registration, so unrelated settings edits don't churn hotkeys
    private static func hotKeySignature(_ settings: CaptureSettings) -> [String] {
        bindings(from: settings).map { "\($0.action.rawValue)|\($0.binding.displayString)" }
    }

    private static func bindings(from settings: CaptureSettings) -> [(action: CaptureActionType, binding: ShortcutBinding)] {
        var result: [(CaptureActionType, ShortcutBinding)] = [
            (.region, settings.shortcutRegion),
            (.fullScreen, settings.shortcutFullScreen),
            (.window, settings.shortcutWindow),
            (.recording, settings.shortcutRecording),
            (.ocr, settings.shortcutQuickOcr)
        ]
        for custom in settings.customShortcuts {
            if let action = CaptureActionType(customActionName: custom.action) {
                result.append((action, custom.binding))
            }
        }
        return result.filter { !$0.1.isMacOSScreenshotShortcut }
    }

    private func registerHotKeys(from settings: CaptureSettings) {
        unregisterHotKeys()

        var seen = Set<String>()
        var failures: [String] = []
        var nextID: UInt32 = 1

        for (action, binding) in Self.bindings(from: settings) {
            guard binding.isValidGlobalHotKey, let keyCode = binding.keyCode else { continue }
            let identity = "\(keyCode)-\(binding.carbonModifiers)"
            guard seen.insert(identity).inserted else { continue }

            let hotKeyID = EventHotKeyID(signature: Self.signature, id: nextID)
            var hotKeyRef: EventHotKeyRef?
            let status = RegisterEventHotKey(UInt32(keyCode), binding.carbonModifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)

            if status == noErr, let ref = hotKeyRef {
                registeredHotKeyRefs.append(ref)
                actionsByID[nextID] = action
            } else {
                failures.append(binding.displayString)
                AppLogger.shared.capture.notice("Could not register hotkey \(binding.displayString, privacy: .public) (status \(status)).")
            }
            nextID += 1
        }
        failedBindings = failures
    }

    private func unregisterHotKeys() {
        for ref in registeredHotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        registeredHotKeyRefs.removeAll()
        actionsByID.removeAll()
    }

    // MARK: - Dispatch

    public func handleHotKeyTriggered(id: UInt32) {
        guard !isSuspended, let action = actionsByID[id] else { return }
        // Ignore repeats while an overlay is already up
        if CaptureCoordinator.shared.isCapturing && action != .recording { return }
        AppLogger.shared.capture.info("Global shortcut fired: \(action.rawValue, privacy: .public)")
        AppCoordinator.shared.triggerCapture(type: action)
    }
}

extension CaptureActionType {
    /// Maps the action names offered in Settings › Shortcuts › Add New Shortcut to capture actions
    init?(customActionName: String) {
        switch customActionName {
        case "Capture Selected Region": self = .region
        case "Capture Full Screen": self = .fullScreen
        case "Capture Window": self = .window
        case "Record Screen": self = .recording
        case "OCR Text from Screen": self = .ocr
        default: return nil
        }
    }
}
