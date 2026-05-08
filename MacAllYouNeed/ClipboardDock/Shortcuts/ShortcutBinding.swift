import AppKit
import Foundation

struct ShortcutBinding: Codable, Hashable {
    let keyCode: UInt16
    let modifierMask: UInt

    func display() -> String {
        var parts: [String] = []
        let modifiers = NSEvent.ModifierFlags(rawValue: modifierMask)
        if modifiers.contains(.control) { parts.append("⌃") }
        if modifiers.contains(.option) { parts.append("⌥") }
        if modifiers.contains(.shift) { parts.append("⇧") }
        if modifiers.contains(.command) { parts.append("⌘") }
        parts.append(KeyCode.symbol(for: keyCode))
        return parts.joined()
    }
}

private enum KeyCode {
    static func symbol(for code: UInt16) -> String {
        switch code {
        case 49: return "Space"
        case 36: return "↩"
        case 48: return "⇥"
        case 51: return "⌫"
        case 53: return "⎋"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default: return "K\(code)"
        }
    }
}
