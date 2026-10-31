import Foundation
import Carbon.HIToolbox
import AppKit

/// Helpers to render Carbon key codes / modifier masks as human-readable shortcut strings
/// (e.g. "⌘⇧2"), and to translate AppKit modifier flags to Carbon modifier masks.
enum KeyCodes {

    /// Carbon virtual key code -> display glyph for non-letter/number keys.
    private static let special: [Int: String] = [
        kVK_Return: "↩", kVK_Tab: "⇥", kVK_Space: "Space", kVK_Delete: "⌫",
        kVK_Escape: "⎋", kVK_ForwardDelete: "⌦", kVK_Home: "↖", kVK_End: "↘",
        kVK_PageUp: "⇞", kVK_PageDown: "⇟", kVK_LeftArrow: "←", kVK_RightArrow: "→",
        kVK_DownArrow: "↓", kVK_UpArrow: "↑",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5",
        kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10",
        kVK_F11: "F11", kVK_F12: "F12",
    ]

    /// Carbon virtual key code -> character (letters, digits, punctuation).
    private static let ansi: [Int: String] = [
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
        kVK_ANSI_Minus: "-", kVK_ANSI_Equal: "=", kVK_ANSI_LeftBracket: "[",
        kVK_ANSI_RightBracket: "]", kVK_ANSI_Backslash: "\\", kVK_ANSI_Semicolon: ";",
        kVK_ANSI_Quote: "'", kVK_ANSI_Comma: ",", kVK_ANSI_Period: ".", kVK_ANSI_Slash: "/",
        kVK_ANSI_Grave: "`",
    ]

    static func keyString(_ keyCode: UInt32) -> String {
        let code = Int(keyCode)
        if let s = ansi[code] { return s }
        if let s = special[code] { return s }
        return "?"
    }

    /// Render Carbon modifier mask as ordered glyphs (⌃⌥⇧⌘).
    static func modifierString(_ carbonMods: UInt32) -> String {
        var s = ""
        if carbonMods & UInt32(controlKey) != 0 { s += "⌃" }
        if carbonMods & UInt32(optionKey)  != 0 { s += "⌥" }
        if carbonMods & UInt32(shiftKey)   != 0 { s += "⇧" }
        if carbonMods & UInt32(cmdKey)     != 0 { s += "⌘" }
        return s
    }

    static func displayString(_ spec: HotkeySpec) -> String {
        guard spec.enabled, spec.keyCode != 0 || spec.modifiers != 0 else { return "None" }
        return modifierString(spec.modifiers) + keyString(spec.keyCode)
    }

    /// Convert AppKit event modifier flags to a Carbon modifier mask.
    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var mods: UInt32 = 0
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        if flags.contains(.shift)   { mods |= UInt32(shiftKey) }
        if flags.contains(.option)  { mods |= UInt32(optionKey) }
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        return mods
    }

    /// A key code counts as a modifier-only press we should ignore while recording.
    static func isModifierKey(_ keyCode: UInt16) -> Bool {
        switch Int(keyCode) {
        case kVK_Command, kVK_RightCommand, kVK_Shift, kVK_RightShift,
             kVK_Option, kVK_RightOption, kVK_Control, kVK_RightControl,
             kVK_Function, kVK_CapsLock:
            return true
        default:
            return false
        }
    }
}
