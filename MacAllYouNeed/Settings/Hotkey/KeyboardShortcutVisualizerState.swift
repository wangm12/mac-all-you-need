import AppKit
import Carbon.HIToolbox
import Core
import CoreGraphics
import Platform

enum KeyboardShortcutVisualizerKeyID: Hashable {
    case fn
    case genericControl
    case leftControl
    case rightControl
    case genericOption
    case leftOption
    case rightOption
    case genericCommand
    case leftCommand
    case rightCommand
    case genericShift
    case leftShift
    case rightShift
    case keyCode(UInt16)
}

struct KeyboardShortcutVisualizerState: Equatable {
    var isRecording: Bool
    var pressedKeys: Set<KeyboardShortcutVisualizerKeyID>

    static let inactive = KeyboardShortcutVisualizerState(isRecording: false, pressedKeys: [])

    static func recording(keyCode: UInt16? = nil, cgFlags: CGEventFlags = []) -> KeyboardShortcutVisualizerState {
        var pressedKeys = physicalModifierKeys(from: cgFlags, keyCode: keyCode)
        if let keyCode, !isModifierKeyCode(keyCode) {
            pressedKeys.insert(.keyCode(keyCode))
        }
        return KeyboardShortcutVisualizerState(isRecording: true, pressedKeys: pressedKeys)
    }

    static func recording(
        keyCode: UInt16? = nil,
        modifierFlags: NSEvent.ModifierFlags
    ) -> KeyboardShortcutVisualizerState {
        var pressedKeys = fallbackModifierKeys(from: modifierFlags, keyCode: keyCode)
        if let keyCode, !isModifierKeyCode(keyCode) {
            pressedKeys.insert(.keyCode(keyCode))
        }
        return KeyboardShortcutVisualizerState(isRecording: true, pressedKeys: pressedKeys)
    }

    private static func physicalModifierKeys(
        from flags: CGEventFlags,
        keyCode: UInt16?
    ) -> Set<KeyboardShortcutVisualizerKeyID> {
        let rawFlags = flags.rawValue
        var keys: Set<KeyboardShortcutVisualizerKeyID> = []

        let leftControl = rawFlags & CGModifierDeviceBit.leftControl != 0
        let leftShift = rawFlags & CGModifierDeviceBit.leftShift != 0
        let rightShift = rawFlags & CGModifierDeviceBit.rightShift != 0
        let leftCommand = rawFlags & CGModifierDeviceBit.leftCommand != 0
        let rightCommand = rawFlags & CGModifierDeviceBit.rightCommand != 0
        let leftOption = rawFlags & CGModifierDeviceBit.leftOption != 0
        let rightOption = rawFlags & CGModifierDeviceBit.rightOption != 0
        let rightControl = rawFlags & CGModifierDeviceBit.rightControl != 0

        if leftControl || (flags.contains(.maskControl) && !rightControl) { keys.insert(.leftControl) }
        if rightControl { keys.insert(.rightControl) }
        if leftOption || (flags.contains(.maskAlternate) && !rightOption) { keys.insert(.leftOption) }
        if rightOption { keys.insert(.rightOption) }
        if leftCommand || (flags.contains(.maskCommand) && !rightCommand) { keys.insert(.leftCommand) }
        if rightCommand { keys.insert(.rightCommand) }
        if leftShift || (flags.contains(.maskShift) && !rightShift) { keys.insert(.leftShift) }
        if rightShift { keys.insert(.rightShift) }
        if flags.contains(.maskSecondaryFn), !suppressesSpuriousFnIndicator(for: keyCode) {
            keys.insert(.fn)
        }

        return keys
    }

    private static func fallbackModifierKeys(
        from flags: NSEvent.ModifierFlags,
        keyCode: UInt16?
    ) -> Set<KeyboardShortcutVisualizerKeyID> {
        var keys: Set<KeyboardShortcutVisualizerKeyID> = []
        if flags.contains(.control) { keys.insert(.genericControl) }
        if flags.contains(.option) { keys.insert(.genericOption) }
        if flags.contains(.command) { keys.insert(.genericCommand) }
        if flags.contains(.shift) { keys.insert(.genericShift) }
        if flags.contains(.function), !suppressesSpuriousFnIndicator(for: keyCode) {
            keys.insert(.fn)
        }
        return keys
    }

    /// MacBook arrow/F-keys often set `maskSecondaryFn` without a deliberate Fn press.
    /// Hide that bit in the on-screen keyboard while recording those keys.
    private static func suppressesSpuriousFnIndicator(for keyCode: UInt16?) -> Bool {
        guard let keyCode else { return false }
        return isFnSpecialKey(keyCode)
    }

    private static func isFnSpecialKey(_ keyCode: UInt16) -> Bool {
        switch Int(keyCode) {
        case kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow,
             kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8,
             kVK_F9, kVK_F10, kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15,
             kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20,
             kVK_Help, kVK_ForwardDelete:
            true
        default:
            false
        }
    }

    private static func isModifierKeyCode(_ keyCode: UInt16) -> Bool {
        switch Int(keyCode) {
        case kVK_Function, kVK_Control, kVK_RightControl, kVK_Option, kVK_RightOption,
             kVK_Command, kVK_RightCommand, kVK_Shift, kVK_RightShift, kVK_CapsLock:
            true
        default:
            false
        }
    }
}
