import Foundation

enum ShortcutAction: String, CaseIterable, Identifiable {
    case focusSearch
    case togglePin
    case addToList
    case deleteFocused
    case quickLook
    case cycleFocus
    case dismiss
    case paste
    case pastePlain
    case extendSelectionLeft
    case extendSelectionRight
    case jumpToFirst
    case jumpToLast
    case toggleCheatsheet
    case transformFocused
    case suspendCapture

    var id: String { rawValue }

    var label: String {
        switch self {
        case .focusSearch:
            return "Focus search field"
        case .togglePin:
            return "Pin / unpin focused item"
        case .addToList:
            return "Add focused / selected to list"
        case .deleteFocused:
            return "Delete focused item"
        case .quickLook:
            return "Quick Look"
        case .cycleFocus:
            return "Cycle focus area"
        case .dismiss:
            return "Dismiss dock"
        case .paste:
            return "Paste focused (or merge selection)"
        case .pastePlain:
            return "Paste as plain text"
        case .extendSelectionLeft:
            return "Extend selection left"
        case .extendSelectionRight:
            return "Extend selection right"
        case .jumpToFirst:
            return "Jump to first item"
        case .jumpToLast:
            return "Jump to last item"
        case .toggleCheatsheet:
            return "Toggle keyboard cheatsheet"
        case .transformFocused:
            return "Transform focused item"
        case .suspendCapture:
            return "Suspend capture for 60 seconds"
        }
    }
}
