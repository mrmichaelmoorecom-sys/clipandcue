import AppKit
import Carbon.HIToolbox

/// Converts a (keyCode, Carbon-modifiers) pair into a display string like
/// `⌘⌥V`. Used by `HotkeyRecorderView` to show the bound shortcut.
enum HotkeyFormatter {
    static func display(keyCode: Int, modifiers: Int) -> String {
        modifiersString(modifiers) + keyString(keyCode)
    }

    static func modifiersString(_ mods: Int) -> String {
        var s = ""
        if mods & Int(controlKey) != 0 { s += "⌃" }
        if mods & Int(optionKey)  != 0 { s += "⌥" }
        if mods & Int(shiftKey)   != 0 { s += "⇧" }
        if mods & Int(cmdKey)     != 0 { s += "⌘" }
        return s
    }

    static func keyString(_ keyCode: Int) -> String {
        Self.map[keyCode] ?? "·"
    }

    /// Map of the common keys you'd realistically bind a global hotkey to.
    /// Unknown / exotic keys fall back to "·".
    private static let map: [Int: String] = [
        kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D",
        kVK_ANSI_E: "E", kVK_ANSI_F: "F", kVK_ANSI_G: "G", kVK_ANSI_H: "H",
        kVK_ANSI_I: "I", kVK_ANSI_J: "J", kVK_ANSI_K: "K", kVK_ANSI_L: "L",
        kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O", kVK_ANSI_P: "P",
        kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T",
        kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X",
        kVK_ANSI_Y: "Y", kVK_ANSI_Z: "Z",
        kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3",
        kVK_ANSI_4: "4", kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7",
        kVK_ANSI_8: "8", kVK_ANSI_9: "9",
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Escape: "⎋",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4",
        kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8",
        kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        kVK_LeftArrow: "←", kVK_RightArrow: "→",
        kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_ANSI_LeftBracket: "[", kVK_ANSI_RightBracket: "]",
        kVK_ANSI_Slash: "/", kVK_ANSI_Backslash: "\\",
        kVK_ANSI_Semicolon: ";", kVK_ANSI_Quote: "'",
        kVK_ANSI_Comma: ",", kVK_ANSI_Period: ".",
        kVK_ANSI_Minus: "-", kVK_ANSI_Equal: "=",
        kVK_ANSI_Grave: "`"
    ]

    /// Convert NSEvent modifier flags into Carbon's modifier mask Int.
    static func carbonModifiers(from nsMods: NSEvent.ModifierFlags) -> Int {
        var c = 0
        if nsMods.contains(.command) { c |= Int(cmdKey) }
        if nsMods.contains(.option)  { c |= Int(optionKey) }
        if nsMods.contains(.control) { c |= Int(controlKey) }
        if nsMods.contains(.shift)   { c |= Int(shiftKey) }
        return c
    }
}
