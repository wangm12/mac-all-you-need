import Foundation
import Platform

enum ShortcutDefaults {
    static func defaultBindings(for action: ShortcutAction) -> [HotkeyDescriptor] {
        switch action {
        case .focusSearch:
            return [HotkeyDescriptor(keyCode: 3, modifiers: [.command])]
        case .togglePin:
            return [HotkeyDescriptor(keyCode: 35, modifiers: [.command])]
        case .addToList:
            return [HotkeyDescriptor(keyCode: 37, modifiers: [.command])]
        case .deleteFocused:
            return [HotkeyDescriptor(keyCode: 51, modifiers: [.command])]
        case .quickLook:
            return [HotkeyDescriptor(keyCode: 49, modifiers: [])]
        case .cycleFocus:
            return [HotkeyDescriptor(keyCode: 48, modifiers: [])]
        case .dismiss:
            return [HotkeyDescriptor(keyCode: 53, modifiers: [])]
        case .paste:
            return [HotkeyDescriptor(keyCode: 36, modifiers: [])]
        case .pastePlain:
            return [HotkeyDescriptor(keyCode: 36, modifiers: [.option])]
        case .extendSelectionLeft:
            return [HotkeyDescriptor(keyCode: 123, modifiers: [.shift])]
        case .extendSelectionRight:
            return [HotkeyDescriptor(keyCode: 124, modifiers: [.shift])]
        case .jumpToFirst:
            return [HotkeyDescriptor(keyCode: 123, modifiers: [.command])]
        case .jumpToLast:
            return [HotkeyDescriptor(keyCode: 124, modifiers: [.command])]
        case .toggleCheatsheet:
            return [HotkeyDescriptor(keyCode: 44, modifiers: [.command, .shift])]
        case .transformFocused:
            return [HotkeyDescriptor(keyCode: 17, modifiers: [.command])]
        case .suspendCapture:
            return []
        case .copySmartText:
            return [HotkeyDescriptor(keyCode: 8, modifiers: [.command, .shift])]
        }
    }
}
