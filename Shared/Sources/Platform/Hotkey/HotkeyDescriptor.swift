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

    public init(keyCode: UInt32, modifiers: Modifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public static let defaultClipboard = HotkeyDescriptor(keyCode: UInt32(kVK_ANSI_V), modifiers: [.command, .shift])
    public static let defaultDownload = HotkeyDescriptor(keyCode: UInt32(kVK_ANSI_D), modifiers: [.command, .shift])
    public static let defaultFolder = HotkeyDescriptor(keyCode: UInt32(kVK_ANSI_F), modifiers: [.command, .shift])

    public var display: String {
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
