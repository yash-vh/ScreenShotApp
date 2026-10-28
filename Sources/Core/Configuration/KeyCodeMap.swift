import Foundation
import Carbon.HIToolbox

/// Layout-independent mapping between shortcut key names and macOS virtual key codes.
/// Recording by key code avoids Shift turning "4" into "$" when storing ⇧⌘4.
public enum KeyCodeMap {
    private static let namesByCode: [UInt16: String] = {
        var map: [UInt16: String] = [
            UInt16(kVK_ANSI_A): "A", UInt16(kVK_ANSI_B): "B", UInt16(kVK_ANSI_C): "C", UInt16(kVK_ANSI_D): "D",
            UInt16(kVK_ANSI_E): "E", UInt16(kVK_ANSI_F): "F", UInt16(kVK_ANSI_G): "G", UInt16(kVK_ANSI_H): "H",
            UInt16(kVK_ANSI_I): "I", UInt16(kVK_ANSI_J): "J", UInt16(kVK_ANSI_K): "K", UInt16(kVK_ANSI_L): "L",
            UInt16(kVK_ANSI_M): "M", UInt16(kVK_ANSI_N): "N", UInt16(kVK_ANSI_O): "O", UInt16(kVK_ANSI_P): "P",
            UInt16(kVK_ANSI_Q): "Q", UInt16(kVK_ANSI_R): "R", UInt16(kVK_ANSI_S): "S", UInt16(kVK_ANSI_T): "T",
            UInt16(kVK_ANSI_U): "U", UInt16(kVK_ANSI_V): "V", UInt16(kVK_ANSI_W): "W", UInt16(kVK_ANSI_X): "X",
            UInt16(kVK_ANSI_Y): "Y", UInt16(kVK_ANSI_Z): "Z",
            UInt16(kVK_ANSI_0): "0", UInt16(kVK_ANSI_1): "1", UInt16(kVK_ANSI_2): "2", UInt16(kVK_ANSI_3): "3",
            UInt16(kVK_ANSI_4): "4", UInt16(kVK_ANSI_5): "5", UInt16(kVK_ANSI_6): "6", UInt16(kVK_ANSI_7): "7",
            UInt16(kVK_ANSI_8): "8", UInt16(kVK_ANSI_9): "9",
            UInt16(kVK_ANSI_Minus): "-", UInt16(kVK_ANSI_Equal): "=", UInt16(kVK_ANSI_LeftBracket): "[",
            UInt16(kVK_ANSI_RightBracket): "]", UInt16(kVK_ANSI_Semicolon): ";", UInt16(kVK_ANSI_Quote): "'",
            UInt16(kVK_ANSI_Comma): ",", UInt16(kVK_ANSI_Period): ".", UInt16(kVK_ANSI_Slash): "/",
            UInt16(kVK_ANSI_Backslash): "\\", UInt16(kVK_ANSI_Grave): "`",
            UInt16(kVK_Escape): "Esc", UInt16(kVK_Return): "Return", UInt16(kVK_Space): "Space",
            UInt16(kVK_Tab): "Tab", UInt16(kVK_Delete): "Delete", UInt16(kVK_ForwardDelete): "⌦",
            UInt16(kVK_LeftArrow): "←", UInt16(kVK_RightArrow): "→", UInt16(kVK_DownArrow): "↓", UInt16(kVK_UpArrow): "↑",
            UInt16(kVK_Home): "Home", UInt16(kVK_End): "End", UInt16(kVK_PageUp): "PgUp", UInt16(kVK_PageDown): "PgDn"
        ]
        let functionKeys = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
                            kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19]
        for (index, code) in functionKeys.enumerated() {
            map[UInt16(code)] = "F\(index + 1)"
        }
        return map
    }()

    private static let codesByName: [String: UInt16] = {
        var map = Dictionary(uniqueKeysWithValues: namesByCode.map { ($0.value.uppercased(), $0.key) })
        // Legacy bindings recorded the Shift-modified character (e.g. "$" for ⇧4)
        let shifted: [String: Int] = [
            "!": kVK_ANSI_1, "@": kVK_ANSI_2, "#": kVK_ANSI_3, "$": kVK_ANSI_4, "%": kVK_ANSI_5,
            "^": kVK_ANSI_6, "&": kVK_ANSI_7, "*": kVK_ANSI_8, "(": kVK_ANSI_9, ")": kVK_ANSI_0,
            "_": kVK_ANSI_Minus, "+": kVK_ANSI_Equal, "{": kVK_ANSI_LeftBracket, "}": kVK_ANSI_RightBracket,
            ":": kVK_ANSI_Semicolon, "\"": kVK_ANSI_Quote, "<": kVK_ANSI_Comma, ">": kVK_ANSI_Period,
            "?": kVK_ANSI_Slash, "|": kVK_ANSI_Backslash, "~": kVK_ANSI_Grave
        ]
        for (name, code) in shifted { map[name] = UInt16(code) }
        map["ESCAPE"] = UInt16(kVK_Escape)
        map["ENTER"] = UInt16(kVK_Return)
        return map
    }()

    /// Display name for a virtual key code, if it is a supported shortcut key
    public static func name(for keyCode: UInt16) -> String? {
        namesByCode[keyCode]
    }

    /// Virtual key code for a stored key name (case-insensitive)
    public static func keyCode(for name: String) -> UInt16? {
        codesByName[name.uppercased()]
    }

    /// Canonical display name for a stored key (maps legacy shifted symbols such as "$" back to "4")
    public static func canonicalName(for name: String) -> String {
        guard let code = keyCode(for: name), let canonical = namesByCode[code] else { return name }
        return canonical
    }
}
