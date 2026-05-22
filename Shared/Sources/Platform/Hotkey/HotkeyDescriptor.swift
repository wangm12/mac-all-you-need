import Carbon.HIToolbox
import Foundation

public struct HotkeyDescriptor: Hashable, Codable, Sendable {
    public struct Modifiers: OptionSet, Codable, Hashable, Sendable {
        public let rawValue: UInt32
        public init(rawValue: UInt32) {
            self.rawValue = rawValue
        }

        public static let command = Modifiers(rawValue: UInt32(cmdKey))
        public static let option = Modifiers(rawValue: UInt32(optionKey))
        public static let control = Modifiers(rawValue: UInt32(controlKey))
        public static let shift = Modifiers(rawValue: UInt32(shiftKey))
    }

    public let keyCode: UInt32
    public let modifiers: Modifiers
    /// Non-nil when this descriptor represents a modifier-tap shortcut.
    /// When set, `keyCode` and `modifiers` are unused for registration.
    public let modifierTap: ModifierTapShortcut?

    public var isModifierTap: Bool { modifierTap != nil }

    public init(keyCode: UInt32, modifiers: Modifiers, modifierTap: ModifierTapShortcut? = nil) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.modifierTap = modifierTap
    }

    // Convenience for modifier-tap descriptors (keyCode/modifiers unused).
    public init(modifierTap: ModifierTapShortcut) {
        self.keyCode = 0
        self.modifiers = []
        self.modifierTap = modifierTap
    }

    public static let defaultClipboard = HotkeyDescriptor(keyCode: UInt32(kVK_ANSI_V), modifiers: [.command, .shift])
    public static let defaultDownload = HotkeyDescriptor(keyCode: UInt32(kVK_ANSI_D), modifiers: [.command, .shift])
    public static let defaultFolder = HotkeyDescriptor(keyCode: UInt32(kVK_ANSI_F), modifiers: [.command, .shift])

    public var display: String {
        if let tap = modifierTap {
            let glyph = tap.key.glyph
            return tap.count > 1 ? "\(glyph) ×\(tap.count)" : glyph
        }
        var s = ""
        if modifiers.contains(.control) { s += "⌃" }
        if modifiers.contains(.option) { s += "⌥" }
        if modifiers.contains(.shift) { s += "⇧" }
        if modifiers.contains(.command) { s += "⌘" }
        s += Self.keyDisplay(keyCode)
        return s
    }

    private static func keyDisplay(_ code: UInt32) -> String {
        switch Int(code) {
        case kVK_ANSI_A: "A"
        case kVK_ANSI_B: "B"
        case kVK_ANSI_C: "C"
        case kVK_ANSI_D: "D"
        case kVK_ANSI_E: "E"
        case kVK_ANSI_F: "F"
        case kVK_ANSI_G: "G"
        case kVK_ANSI_H: "H"
        case kVK_ANSI_I: "I"
        case kVK_ANSI_J: "J"
        case kVK_ANSI_K: "K"
        case kVK_ANSI_L: "L"
        case kVK_ANSI_M: "M"
        case kVK_ANSI_N: "N"
        case kVK_ANSI_O: "O"
        case kVK_ANSI_P: "P"
        case kVK_ANSI_Q: "Q"
        case kVK_ANSI_R: "R"
        case kVK_ANSI_S: "S"
        case kVK_ANSI_T: "T"
        case kVK_ANSI_U: "U"
        case kVK_ANSI_V: "V"
        case kVK_ANSI_W: "W"
        case kVK_ANSI_X: "X"
        case kVK_ANSI_Y: "Y"
        case kVK_ANSI_Z: "Z"
        case kVK_Space: "Space"
        case kVK_Return: "Return"
        case kVK_Tab: "Tab"
        case kVK_Escape: "Esc"
        case kVK_LeftArrow: "←"
        case kVK_RightArrow: "→"
        case kVK_UpArrow: "↑"
        case kVK_DownArrow: "↓"
        default: "?"
        }
    }
}

// MARK: - Modifier tap shortcut

/// Describes a global shortcut triggered by tapping (pressing and quickly
/// releasing) a single modifier key, optionally multiple times in succession.
public struct ModifierTapShortcut: Hashable, Codable, Sendable {
    public enum Key: String, Codable, Sendable, CaseIterable {
        case command
        case option
        case control
        case shift
        case fn
        case leftCommand
        case rightCommand
        case leftOption
        case rightOption
        case leftControl
        case rightControl
        case leftShift
        case rightShift

        /// Display glyph shown in the UI (e.g. "⌘", "Left ⌘").
        public var glyph: String {
            switch self {
            case .command:      "⌘"
            case .option:       "⌥"
            case .control:      "⌃"
            case .shift:        "⇧"
            case .fn:           "Fn"
            case .leftCommand:  "Left ⌘"
            case .rightCommand: "Right ⌘"
            case .leftOption:   "Left ⌥"
            case .rightOption:  "Right ⌥"
            case .leftControl:  "Left ⌃"
            case .rightControl: "Right ⌃"
            case .leftShift:    "Left ⇧"
            case .rightShift:   "Right ⇧"
            }
        }
    }

    /// The modifier key that must be tapped.
    public let key: Key
    /// Number of consecutive taps required (1 = single, 2 = double).
    public let count: Int

    public init(key: Key, count: Int = 1) {
        self.key = key
        self.count = max(1, min(count, 2))
    }

    public static func singleTap(_ key: Key) -> ModifierTapShortcut {
        ModifierTapShortcut(key: key, count: 1)
    }

    public static func doubleTap(_ key: Key) -> ModifierTapShortcut {
        ModifierTapShortcut(key: key, count: 2)
    }
}
