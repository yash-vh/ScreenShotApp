import Foundation

/// Image format options for exported screenshots
public enum ExportFormat: String, Codable, Sendable, CaseIterable {
    case png = "png"
    case jpeg = "jpeg"

    public var displayName: String {
        switch self {
        case .png: return "PNG (Lossless)"
        case .jpeg: return "JPEG (Compressed)"
        }
    }
}

/// Redaction style options
public enum DefaultRedactionStyle: String, Codable, Sendable, CaseIterable {
    case blur = "blur"
    case pixelate = "pixelate"

    public var displayName: String {
        switch self {
        case .blur: return "Gaussian Blur"
        case .pixelate: return "Pixelation Mosaic"
        }
    }
}

/// Global shortcut representation
public struct ShortcutBinding: Codable, Sendable, Equatable {
    public var key: String
    public var modifiers: [String]

    public init(key: String, modifiers: [String]) {
        self.key = key
        self.modifiers = modifiers
    }

    public var displayString: String {
        modifiers.joined() + key
    }
}

/// Encapsulates user preferences for screenshot capture & post-capture workflow
public struct CaptureSettings: Codable, Sendable, Equatable {
    public var defaultFormat: ExportFormat
    public var jpegQuality: Double
    public var copyToClipboard: Bool
    public var openInEditor: Bool
    public var saveToDisk: Bool
    public var playCaptureSound: Bool
    public var showMagnifier: Bool
    public var runOcrAutomatically: Bool
    public var defaultRedactionStyle: DefaultRedactionStyle
    public var customSaveDirectory: String?

    // Global Shortcuts
    public var shortcutRegion: ShortcutBinding
    public var shortcutFullScreen: ShortcutBinding
    public var shortcutWindow: ShortcutBinding
    public var shortcutRecording: ShortcutBinding
    public var shortcutQuickOcr: ShortcutBinding

    public init(
        defaultFormat: ExportFormat = .png,
        jpegQuality: Double = 0.85,
        copyToClipboard: Bool = true,
        openInEditor: Bool = true,
        saveToDisk: Bool = true,
        playCaptureSound: Bool = true,
        showMagnifier: Bool = true,
        runOcrAutomatically: Bool = true,
        defaultRedactionStyle: DefaultRedactionStyle = .blur,
        customSaveDirectory: String? = nil,
        shortcutRegion: ShortcutBinding = ShortcutBinding(key: "4", modifiers: ["⇧", "⌘"]),
        shortcutFullScreen: ShortcutBinding = ShortcutBinding(key: "3", modifiers: ["⇧", "⌘"]),
        shortcutWindow: ShortcutBinding = ShortcutBinding(key: "5", modifiers: ["⇧", "⌘"]),
        shortcutRecording: ShortcutBinding = ShortcutBinding(key: "6", modifiers: ["⇧", "⌘"]),
        shortcutQuickOcr: ShortcutBinding = ShortcutBinding(key: "7", modifiers: ["⇧", "⌘"])
    ) {
        self.defaultFormat = defaultFormat
        self.jpegQuality = jpegQuality
        self.copyToClipboard = copyToClipboard
        self.openInEditor = openInEditor
        self.saveToDisk = saveToDisk
        self.playCaptureSound = playCaptureSound
        self.showMagnifier = showMagnifier
        self.runOcrAutomatically = runOcrAutomatically
        self.defaultRedactionStyle = defaultRedactionStyle
        self.customSaveDirectory = customSaveDirectory
        self.shortcutRegion = shortcutRegion
        self.shortcutFullScreen = shortcutFullScreen
        self.shortcutWindow = shortcutWindow
        self.shortcutRecording = shortcutRecording
        self.shortcutQuickOcr = shortcutQuickOcr
    }

    public static let `default` = CaptureSettings()
}
