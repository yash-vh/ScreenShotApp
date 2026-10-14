import AppKit
import Carbon

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

/// Robust global hotkey manager combining Carbon RegisterEventHotKey and AppKit monitors.
/// Works from any running macOS application without requiring extra Accessibility permissions.
@MainActor
public final class HotKeyManager {
    public static let shared = HotKeyManager()

    // Carbon event refs
    private var eventHandlerRef: EventHandlerRef?
    private var registeredHotKeyRefs: [EventHotKeyRef] = []

    // AppKit monitors
    private var globalMonitor: Any?
    private var localMonitor: Any?

    public enum ActionID: UInt32 {
        case region = 1
        case fullScreen = 2
        case window = 3
        case recording = 4
        case ocr = 5

        case regionAlt = 11
        case fullScreenAlt = 12
        case windowAlt = 13
        case recordingAlt = 14
        case ocrAlt = 15
    }

    private init() {}

    // MARK: - Lifecycle

    public func startMonitoring() {
        stopMonitoring()

        // 1. Install Carbon event handler
        installCarbonEventHandler()

        // 2. Register system-wide Carbon hotkeys
        registerCarbonHotKeys()

        // 3. Register AppKit Local Monitor (when ScreenshotApp is active)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.handleNSEvent(event) == true {
                return nil // Consume event
            }
            return event
        }

        // 4. Register AppKit Global Monitor (as additional fallback)
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleNSEvent(event)
            }
        }

        AppLogger.shared.capture.info("Keyboard shortcut monitoring successfully registered (Carbon + NSEvent).")
    }

    public func stopMonitoring() {
        // Unregister Carbon HotKeys
        for ref in registeredHotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        registeredHotKeyRefs.removeAll()

        if let handler = eventHandlerRef {
            RemoveEventHandler(handler)
            eventHandlerRef = nil
        }

        // Remove AppKit monitors
        if let local = localMonitor {
            NSEvent.removeMonitor(local)
            localMonitor = nil
        }
        if let global = globalMonitor {
            NSEvent.removeMonitor(global)
            globalMonitor = nil
        }
    }

    // MARK: - Carbon Registration

    private func installCarbonEventHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            carbonHotKeyEventHandler,
            1,
            &eventType,
            nil,
            &eventHandlerRef
        )
    }

    private func registerCarbonHotKeys() {
        let signature = OSType(0x534E4150) // 'SNAP'

        // Modifiers
        let shiftCmd = UInt32(cmdKey | shiftKey)
        let optionCmd = UInt32(cmdKey | optionKey)

        // Standard Shift+Cmd shortcuts
        registerSingleHotKey(keyCode: UInt32(kVK_ANSI_4), modifiers: shiftCmd, id: .region, signature: signature)
        registerSingleHotKey(keyCode: UInt32(kVK_ANSI_3), modifiers: shiftCmd, id: .fullScreen, signature: signature)
        registerSingleHotKey(keyCode: UInt32(kVK_ANSI_5), modifiers: shiftCmd, id: .window, signature: signature)
        registerSingleHotKey(keyCode: UInt32(kVK_ANSI_6), modifiers: shiftCmd, id: .recording, signature: signature)
        registerSingleHotKey(keyCode: UInt32(kVK_ANSI_7), modifiers: shiftCmd, id: .ocr, signature: signature)

        // Safe Option+Cmd (Alt+Cmd) shortcuts (so they are NEVER blocked by macOS built-in screenshot utility)
        registerSingleHotKey(keyCode: UInt32(kVK_ANSI_4), modifiers: optionCmd, id: .regionAlt, signature: signature)
        registerSingleHotKey(keyCode: UInt32(kVK_ANSI_3), modifiers: optionCmd, id: .fullScreenAlt, signature: signature)
        registerSingleHotKey(keyCode: UInt32(kVK_ANSI_5), modifiers: optionCmd, id: .windowAlt, signature: signature)
        registerSingleHotKey(keyCode: UInt32(kVK_ANSI_6), modifiers: optionCmd, id: .recordingAlt, signature: signature)
        registerSingleHotKey(keyCode: UInt32(kVK_ANSI_7), modifiers: optionCmd, id: .ocrAlt, signature: signature)
    }

    private func registerSingleHotKey(keyCode: UInt32, modifiers: UInt32, id: ActionID, signature: OSType) {
        let hotKeyID = EventHotKeyID(signature: signature, id: id.rawValue)
        var hotKeyRef: EventHotKeyRef?
        let err = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        if err == noErr, let ref = hotKeyRef {
            registeredHotKeyRefs.append(ref)
        }
    }

    // MARK: - Event Dispatchers

    public func handleHotKeyTriggered(id: UInt32) {
        guard let action = ActionID(rawValue: id) else { return }

        switch action {
        case .region, .regionAlt:
            AppLogger.shared.capture.info("Global shortcut fired: Region Capture")
            CaptureCoordinator.shared.captureRegion()

        case .fullScreen, .fullScreenAlt:
            AppLogger.shared.capture.info("Global shortcut fired: Full Screen Capture")
            CaptureCoordinator.shared.captureFullScreen()

        case .window, .windowAlt:
            AppLogger.shared.capture.info("Global shortcut fired: Window Capture")
            CaptureCoordinator.shared.captureWindow()

        case .recording, .recordingAlt:
            AppLogger.shared.capture.info("Global shortcut fired: Screen Recording")
            AppCoordinator.shared.triggerCapture(type: .recording)

        case .ocr, .ocrAlt:
            AppLogger.shared.capture.info("Global shortcut fired: OCR Capture")
            AppCoordinator.shared.triggerCapture(type: .ocr)
        }
    }

    @discardableResult
    private func handleNSEvent(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let isCmdShift = flags.contains([.command, .shift])
        let isCmdOption = flags.contains([.command, .option])

        guard isCmdShift || isCmdOption, let chars = event.charactersIgnoringModifiers else {
            return false
        }

        switch chars {
        case "4":
            CaptureCoordinator.shared.captureRegion()
            return true
        case "3":
            CaptureCoordinator.shared.captureFullScreen()
            return true
        case "5":
            CaptureCoordinator.shared.captureWindow()
            return true
        case "6":
            AppCoordinator.shared.triggerCapture(type: .recording)
            return true
        case "7":
            AppCoordinator.shared.triggerCapture(type: .ocr)
            return true
        default:
            return false
        }
    }
}
