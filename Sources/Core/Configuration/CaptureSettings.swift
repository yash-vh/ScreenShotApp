import Foundation
import AppKit
import Carbon.HIToolbox

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

/// Where captures and recordings are saved
public enum SaveLocation: String, Codable, Sendable, CaseIterable, Identifiable {
    case desktop
    case pictures
    case documents
    case downloads
    case custom

    public var id: String { rawValue }

    /// Name of the folder created inside the preset locations
    public static let folderName = "Screenshots"

    public var displayName: String {
        switch self {
        case .desktop: return "Desktop › \(Self.folderName)"
        case .pictures: return "Pictures › \(Self.folderName)"
        case .documents: return "Documents › \(Self.folderName)"
        case .downloads: return "Downloads › \(Self.folderName)"
        case .custom: return "Custom Folder…"
        }
    }

    public var systemImage: String {
        switch self {
        case .desktop: return "menubar.dock.rectangle"
        case .pictures: return "photo"
        case .documents: return "doc"
        case .downloads: return "arrow.down.circle"
        case .custom: return "folder"
        }
    }

    /// Folder for a preset location; nil for `.custom`
    public func presetURL(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL? {
        let parent: String
        switch self {
        case .desktop: parent = "Desktop"
        case .pictures: parent = "Pictures"
        case .documents: parent = "Documents"
        case .downloads: parent = "Downloads"
        case .custom: return nil
        }
        return home.appendingPathComponent(parent, isDirectory: true).appendingPathComponent(Self.folderName, isDirectory: true)
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
        let order = ["⌃", "⌥", "⇧", "⌘"]
        let sortedModifiers = order.filter { modifiers.contains($0) }
        return sortedModifiers.joined() + KeyCodeMap.canonicalName(for: key)
    }

    /// Virtual key code of the bound key, if recognised
    public var keyCode: UInt16? {
        KeyCodeMap.keyCode(for: key)
    }

    /// Carbon modifier mask for `RegisterEventHotKey`
    public var carbonModifiers: UInt32 {
        var mask: UInt32 = 0
        if modifiers.contains("⌘") { mask |= UInt32(cmdKey) }
        if modifiers.contains("⇧") { mask |= UInt32(shiftKey) }
        if modifiers.contains("⌥") { mask |= UInt32(optionKey) }
        if modifiers.contains("⌃") { mask |= UInt32(controlKey) }
        return mask
    }

    /// Whether this binding is usable as a system-wide hotkey (needs ⌘, ⌃ or ⌥, or a function key)
    public var isValidGlobalHotKey: Bool {
        guard keyCode != nil else { return false }
        return modifiers.contains("⌘") || modifiers.contains("⌃") || modifiers.contains("⌥") || key.uppercased().hasPrefix("F")
    }

    public func matches(event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command) == modifiers.contains("⌘"),
              flags.contains(.shift) == modifiers.contains("⇧"),
              flags.contains(.option) == modifiers.contains("⌥"),
              flags.contains(.control) == modifiers.contains("⌃") else {
            return false
        }

        if let code = keyCode {
            return event.keyCode == code
        }
        return event.charactersIgnoringModifiers?.uppercased() == key.uppercased()
    }
}

/// User-defined custom shortcut item
public struct CustomShortcutItem: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID
    public var name: String
    public var action: String
    public var binding: ShortcutBinding

    public init(id: UUID = UUID(), name: String, action: String, binding: ShortcutBinding) {
        self.id = id
        self.name = name
        self.action = action
        self.binding = binding
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
    public var runOcrAutomatically: Bool
    public var defaultRedactionStyle: DefaultRedactionStyle
    public var saveLocation: SaveLocation
    /// Folder used when `saveLocation` is `.custom`
    public var customSaveDirectory: String?
    /// File names look like "<prefix> 2026-10-28 at 14.03.22.png"
    public var fileNamePrefix: String

    // Global Shortcuts
    public var shortcutRegion: ShortcutBinding
    public var shortcutFullScreen: ShortcutBinding
    public var shortcutWindow: ShortcutBinding
    public var shortcutRecording: ShortcutBinding
    public var shortcutQuickOcr: ShortcutBinding
    public var shortcutCopy: ShortcutBinding
    public var shortcutUpload: ShortcutBinding
    public var shortcutCancel: ShortcutBinding
    public var customShortcuts: [CustomShortcutItem]

    public init(
        defaultFormat: ExportFormat = .png,
        jpegQuality: Double = 0.85,
        copyToClipboard: Bool = true,
        openInEditor: Bool = true,
        saveToDisk: Bool = true,
        playCaptureSound: Bool = true,
        runOcrAutomatically: Bool = true,
        defaultRedactionStyle: DefaultRedactionStyle = .blur,
        saveLocation: SaveLocation = .desktop,
        customSaveDirectory: String? = nil,
        fileNamePrefix: String = "Screenshot",
        shortcutRegion: ShortcutBinding = ShortcutBinding(key: "4", modifiers: ["⇧", "⌘"]),
        shortcutFullScreen: ShortcutBinding = ShortcutBinding(key: "3", modifiers: ["⇧", "⌘"]),
        shortcutWindow: ShortcutBinding = ShortcutBinding(key: "5", modifiers: ["⇧", "⌘"]),
        shortcutRecording: ShortcutBinding = ShortcutBinding(key: "6", modifiers: ["⇧", "⌘"]),
        shortcutQuickOcr: ShortcutBinding = ShortcutBinding(key: "7", modifiers: ["⇧", "⌘"]),
        shortcutCopy: ShortcutBinding = ShortcutBinding(key: "C", modifiers: ["⌘"]),
        shortcutUpload: ShortcutBinding = ShortcutBinding(key: "U", modifiers: ["⌘"]),
        shortcutCancel: ShortcutBinding = ShortcutBinding(key: "Esc", modifiers: []),
        customShortcuts: [CustomShortcutItem] = []
    ) {
        self.defaultFormat = defaultFormat
        self.jpegQuality = jpegQuality
        self.copyToClipboard = copyToClipboard
        self.openInEditor = openInEditor
        self.saveToDisk = saveToDisk
        self.playCaptureSound = playCaptureSound
        self.runOcrAutomatically = runOcrAutomatically
        self.defaultRedactionStyle = defaultRedactionStyle
        self.saveLocation = saveLocation
        self.customSaveDirectory = customSaveDirectory
        self.fileNamePrefix = fileNamePrefix
        self.shortcutRegion = shortcutRegion
        self.shortcutFullScreen = shortcutFullScreen
        self.shortcutWindow = shortcutWindow
        self.shortcutRecording = shortcutRecording
        self.shortcutQuickOcr = shortcutQuickOcr
        self.shortcutCopy = shortcutCopy
        self.shortcutUpload = shortcutUpload
        self.shortcutCancel = shortcutCancel
        self.customShortcuts = customShortcuts
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.defaultFormat = try container.decodeIfPresent(ExportFormat.self, forKey: .defaultFormat) ?? .png
        self.jpegQuality = try container.decodeIfPresent(Double.self, forKey: .jpegQuality) ?? 0.85
        self.copyToClipboard = try container.decodeIfPresent(Bool.self, forKey: .copyToClipboard) ?? true
        self.openInEditor = try container.decodeIfPresent(Bool.self, forKey: .openInEditor) ?? true
        self.saveToDisk = try container.decodeIfPresent(Bool.self, forKey: .saveToDisk) ?? true
        self.playCaptureSound = try container.decodeIfPresent(Bool.self, forKey: .playCaptureSound) ?? true
        self.runOcrAutomatically = try container.decodeIfPresent(Bool.self, forKey: .runOcrAutomatically) ?? true
        self.defaultRedactionStyle = try container.decodeIfPresent(DefaultRedactionStyle.self, forKey: .defaultRedactionStyle) ?? .blur
        self.customSaveDirectory = try container.decodeIfPresent(String.self, forKey: .customSaveDirectory)
        // Older settings only stored a custom path; keep honouring it
        let legacyCustom = !(customSaveDirectory ?? "").isEmpty
        self.saveLocation = try container.decodeIfPresent(SaveLocation.self, forKey: .saveLocation) ?? (legacyCustom ? .custom : .desktop)
        self.fileNamePrefix = try container.decodeIfPresent(String.self, forKey: .fileNamePrefix) ?? "Screenshot"
        self.shortcutRegion = try container.decodeIfPresent(ShortcutBinding.self, forKey: .shortcutRegion) ?? ShortcutBinding(key: "4", modifiers: ["⇧", "⌘"])
        self.shortcutFullScreen = try container.decodeIfPresent(ShortcutBinding.self, forKey: .shortcutFullScreen) ?? ShortcutBinding(key: "3", modifiers: ["⇧", "⌘"])
        self.shortcutWindow = try container.decodeIfPresent(ShortcutBinding.self, forKey: .shortcutWindow) ?? ShortcutBinding(key: "5", modifiers: ["⇧", "⌘"])
        self.shortcutRecording = try container.decodeIfPresent(ShortcutBinding.self, forKey: .shortcutRecording) ?? ShortcutBinding(key: "6", modifiers: ["⇧", "⌘"])
        self.shortcutQuickOcr = try container.decodeIfPresent(ShortcutBinding.self, forKey: .shortcutQuickOcr) ?? ShortcutBinding(key: "7", modifiers: ["⇧", "⌘"])
        self.shortcutCopy = try container.decodeIfPresent(ShortcutBinding.self, forKey: .shortcutCopy) ?? ShortcutBinding(key: "C", modifiers: ["⌘"])
        self.shortcutUpload = try container.decodeIfPresent(ShortcutBinding.self, forKey: .shortcutUpload) ?? ShortcutBinding(key: "U", modifiers: ["⌘"])
        self.shortcutCancel = try container.decodeIfPresent(ShortcutBinding.self, forKey: .shortcutCancel) ?? ShortcutBinding(key: "Esc", modifiers: [])
        self.customShortcuts = try container.decodeIfPresent([CustomShortcutItem].self, forKey: .customShortcuts) ?? []
    }

    public static let `default` = CaptureSettings()

    /// File-name-safe prefix, falling back to "Screenshot"
    public var sanitizedFileNamePrefix: String {
        let cleaned = fileNamePrefix
            .components(separatedBy: CharacterSet(charactersIn: "/:\\").union(.newlines).union(.controlCharacters))
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? "Screenshot" : cleaned
    }
}
