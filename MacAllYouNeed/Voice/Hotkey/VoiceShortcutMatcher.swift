import AppKit
import Platform

enum VoiceShortcutMatcher {
    static func matches(
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags,
        descriptor: HotkeyDescriptor
    ) -> Bool {
        matches(
            keyCode: keyCode,
            modifiers: modifiers(from: modifierFlags),
            descriptor: descriptor
        )
    }

    static func matches(
        keyCode: UInt16,
        modifiers: HotkeyDescriptor.Modifiers,
        descriptor: HotkeyDescriptor
    ) -> Bool {
        UInt32(keyCode) == descriptor.keyCode && modifiers == descriptor.modifiers
    }

    static func modifiers(from flags: NSEvent.ModifierFlags) -> HotkeyDescriptor.Modifiers {
        var result: HotkeyDescriptor.Modifiers = []
        if flags.contains(.command) { result.insert(.command) }
        if flags.contains(.option) { result.insert(.option) }
        if flags.contains(.control) { result.insert(.control) }
        if flags.contains(.shift) { result.insert(.shift) }
        return result
    }
}
