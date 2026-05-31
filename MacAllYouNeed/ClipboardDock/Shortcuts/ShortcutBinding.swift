import AppKit
import Carbon.HIToolbox
import Foundation
import Platform

/// Legacy persisted dock shortcut shape. New data is stored as `[HotkeyDescriptor]`.
struct LegacyShortcutBinding: Codable, Hashable {
    let keyCode: UInt16
    let modifierMask: UInt

    func asHotkeyDescriptor() -> HotkeyDescriptor {
        let flags = NSEvent.ModifierFlags(rawValue: modifierMask)
        var mods: HotkeyDescriptor.Modifiers = []
        if flags.contains(.command) { mods.insert(.command) }
        if flags.contains(.option) { mods.insert(.option) }
        if flags.contains(.control) { mods.insert(.control) }
        if flags.contains(.shift) { mods.insert(.shift) }
        return HotkeyDescriptor(keyCode: UInt32(keyCode), modifiers: mods)
    }
}

extension HotkeyDescriptor {
    /// Matches combo shortcuts against an `NSEvent` (modifier-tap descriptors never match here).
    func matches(event: NSEvent) -> Bool {
        guard !isModifierTap else { return false }
        let mask = NSEvent.ModifierFlags.deviceIndependentFlagsMask.rawValue
        let eventMods = event.modifierFlags.rawValue & mask
        var mods: UInt = 0
        if modifiers.contains(.command) { mods |= NSEvent.ModifierFlags.command.rawValue }
        if modifiers.contains(.option) { mods |= NSEvent.ModifierFlags.option.rawValue }
        if modifiers.contains(.control) { mods |= NSEvent.ModifierFlags.control.rawValue }
        if modifiers.contains(.shift) { mods |= NSEvent.ModifierFlags.shift.rawValue }
        return UInt32(event.keyCode) == keyCode && mods == eventMods
    }

    func matches(keyCode: UInt16, modifierMask: UInt) -> Bool {
        guard !isModifierTap else { return false }
        let flags = NSEvent.ModifierFlags(rawValue: modifierMask)
        var mods: HotkeyDescriptor.Modifiers = []
        if flags.contains(.command) { mods.insert(.command) }
        if flags.contains(.option) { mods.insert(.option) }
        if flags.contains(.control) { mods.insert(.control) }
        if flags.contains(.shift) { mods.insert(.shift) }
        return UInt32(keyCode) == self.keyCode && mods == modifiers
    }
}
