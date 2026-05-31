import AppKit
import Foundation

enum ShortcutDefaults {
    static func defaultBindings(for action: ShortcutAction) -> [ShortcutBinding] {
        let cmd = NSEvent.ModifierFlags.command.rawValue
        let shift = NSEvent.ModifierFlags.shift.rawValue
        let opt = NSEvent.ModifierFlags.option.rawValue

        switch action {
        case .focusSearch:
            return [ShortcutBinding(keyCode: 3, modifierMask: cmd)]
        case .togglePin:
            return [ShortcutBinding(keyCode: 35, modifierMask: cmd)]
        case .addToList:
            return [ShortcutBinding(keyCode: 37, modifierMask: cmd)]
        case .deleteFocused:
            return [ShortcutBinding(keyCode: 51, modifierMask: cmd)]
        case .quickLook:
            return [ShortcutBinding(keyCode: 49, modifierMask: 0)]
        case .cycleFocus:
            return [ShortcutBinding(keyCode: 48, modifierMask: 0)]
        case .dismiss:
            return [ShortcutBinding(keyCode: 53, modifierMask: 0)]
        case .paste:
            return [ShortcutBinding(keyCode: 36, modifierMask: 0)]
        case .pastePlain:
            return [ShortcutBinding(keyCode: 36, modifierMask: opt)]
        case .extendSelectionLeft:
            return [ShortcutBinding(keyCode: 123, modifierMask: shift)]
        case .extendSelectionRight:
            return [ShortcutBinding(keyCode: 124, modifierMask: shift)]
        case .jumpToFirst:
            return [ShortcutBinding(keyCode: 123, modifierMask: cmd)]
        case .jumpToLast:
            return [ShortcutBinding(keyCode: 124, modifierMask: cmd)]
        case .toggleCheatsheet:
            return [ShortcutBinding(keyCode: 44, modifierMask: cmd | shift)]
        case .transformFocused:
            return [ShortcutBinding(keyCode: 17, modifierMask: cmd)]
        case .suspendCapture:
            return []
        case .copySmartText:
            return [ShortcutBinding(keyCode: 8, modifierMask: cmd | shift)]  // Cmd+Shift+C
        }
    }
}
