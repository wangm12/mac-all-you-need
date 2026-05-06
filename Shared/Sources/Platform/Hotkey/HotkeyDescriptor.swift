import Carbon.HIToolbox
import Foundation

public struct HotkeyDescriptor: Hashable, Codable, Sendable {
    public struct Modifiers: OptionSet, Codable, Hashable, Sendable {
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }
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
        case kVK_ANSI_V: "V"
        case kVK_ANSI_D: "D"
        case kVK_ANSI_F: "F"
        case kVK_ANSI_E: "E"
        default: "?"
        }
    }
}
