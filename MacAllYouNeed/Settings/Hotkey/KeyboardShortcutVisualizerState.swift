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
        var pressedKeys = physicalModifierKeys(from: cgFlags)
        if let keyCode, !isModifierKeyCode(keyCode) {
            pressedKeys.insert(.keyCode(keyCode))
        }
        return KeyboardShortcutVisualizerState(isRecording: true, pressedKeys: pressedKeys)
    }

    static func recording(
        keyCode: UInt16? = nil,
        modifierFlags: NSEvent.ModifierFlags
    ) -> KeyboardShortcutVisualizerState {
        var pressedKeys = fallbackModifierKeys(from: modifierFlags)
        if let keyCode, !isModifierKeyCode(keyCode) {
            pressedKeys.insert(.keyCode(keyCode))
        }
        return KeyboardShortcutVisualizerState(isRecording: true, pressedKeys: pressedKeys)
    }

    private static func physicalModifierKeys(from flags: CGEventFlags) -> Set<KeyboardShortcutVisualizerKeyID> {
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
        if flags.contains(.maskSecondaryFn) { keys.insert(.fn) }

        return keys
    }

    private static func fallbackModifierKeys(from flags: NSEvent.ModifierFlags) -> Set<KeyboardShortcutVisualizerKeyID> {
        var keys: Set<KeyboardShortcutVisualizerKeyID> = []
        if flags.contains(.control) { keys.insert(.genericControl) }
        if flags.contains(.option) { keys.insert(.genericOption) }
        if flags.contains(.command) { keys.insert(.genericCommand) }
        if flags.contains(.shift) { keys.insert(.genericShift) }
        if flags.contains(.function) { keys.insert(.fn) }
        return keys
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
