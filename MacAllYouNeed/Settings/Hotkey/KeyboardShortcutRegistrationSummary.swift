import Core
import Platform

struct KeyboardShortcutRegistrationSummary: Equatable {
    let pressedText: String
    let registeredText: String
    let usesGenericRegistration: Bool
    let registrationNoticeText: String?

    init(state: KeyboardShortcutVisualizerState, candidate: HotkeyDescriptor? = nil) {
        let pressedKeys = state.pressedKeys
        pressedText = Self.physicalDisplay(from: pressedKeys)

        if let candidate, !Self.isPlaceholder(candidate) {
            // Any real candidate (combo or modifier-tap) — show its own
            // display directly. Falling back to `registeredDisplay(from:
            // pressedKeys)` is wrong for combos because pressedKeys only
            // tracks the live modifier state, not the captured key code,
            // so a combo like ⇧⌘1 would render as "⇧ + ⌘ + …".
            registeredText = candidate.display
            usesGenericRegistration = false
            registrationNoticeText = nil
        } else {
            registeredText = Self.registeredDisplay(from: pressedKeys)
            usesGenericRegistration = pressedText != registeredText
                && registeredText != Self.waitingForKeyText
            registrationNoticeText = Self.registrationNotice(from: pressedKeys)
        }
    }

    /// Detect the sentinel placeholder used by HotkeyRecorder when there's
    /// no real candidate yet (so Confirm/Reset/Cancel can still render).
    private static func isPlaceholder(_ descriptor: HotkeyDescriptor) -> Bool {
        descriptor.keyCode == 0
            && descriptor.modifiers.isEmpty
            && descriptor.modifierTap == nil
    }

    private static let waitingText = "Waiting"
    private static let waitingForKeyText = "Waiting for key"

    private static func physicalDisplay(from pressedKeys: Set<KeyboardShortcutVisualizerKeyID>) -> String {
        var parts = orderedPhysicalModifiers(from: pressedKeys)
        if let keyCode = primaryKeyCode(from: pressedKeys) {
            parts.append(keyDisplay(keyCode))
        }
        return parts.isEmpty ? waitingText : parts.joined(separator: " + ")
    }

    private static func registeredDisplay(from pressedKeys: Set<KeyboardShortcutVisualizerKeyID>) -> String {
        var parts: [String] = []
        if containsControl(in: pressedKeys) { parts.append("⌃") }
        if containsOption(in: pressedKeys) { parts.append("⌥") }
        if containsShift(in: pressedKeys) { parts.append("⇧") }
        if containsCommand(in: pressedKeys) { parts.append("⌘") }

        guard let keyCode = primaryKeyCode(from: pressedKeys) else {
            return parts.isEmpty ? waitingForKeyText : parts.joined(separator: " + ") + " + …"
        }

        parts.append(keyDisplay(keyCode))
        return parts.joined(separator: " + ")
    }

    private static func registrationNotice(from pressedKeys: Set<KeyboardShortcutVisualizerKeyID>) -> String? {
        guard primaryKeyCode(from: pressedKeys) != nil else { return nil }
        var notices: [String] = []
        if containsSideSpecificModifier(in: pressedKeys) {
            notices.append("Generic")
        }
        if pressedKeys.contains(.fn) {
            notices.append("Fn ignored")
        }
        return notices.isEmpty ? nil : notices.joined(separator: ", ")
    }

    private static func orderedPhysicalModifiers(from pressedKeys: Set<KeyboardShortcutVisualizerKeyID>) -> [String] {
        var parts: [String] = []
        if pressedKeys.contains(.fn) { parts.append("fn") }
        appendModifierNames(
            to: &parts,
            pressedKeys: pressedKeys,
            generic: .genericControl,
            left: .leftControl,
            right: .rightControl,
            genericName: "⌃",
            leftName: "Left ⌃",
            rightName: "Right ⌃"
        )
        appendModifierNames(
            to: &parts,
            pressedKeys: pressedKeys,
            generic: .genericOption,
            left: .leftOption,
            right: .rightOption,
            genericName: "⌥",
            leftName: "Left ⌥",
            rightName: "Right ⌥"
        )
        appendModifierNames(
            to: &parts,
            pressedKeys: pressedKeys,
            generic: .genericShift,
            left: .leftShift,
            right: .rightShift,
            genericName: "⇧",
            leftName: "Left ⇧",
            rightName: "Right ⇧"
        )
        appendModifierNames(
            to: &parts,
            pressedKeys: pressedKeys,
            generic: .genericCommand,
            left: .leftCommand,
            right: .rightCommand,
            genericName: "⌘",
            leftName: "Left ⌘",
            rightName: "Right ⌘"
        )
        return parts
    }

    private static func appendModifierNames(
        to parts: inout [String],
        pressedKeys: Set<KeyboardShortcutVisualizerKeyID>,
        generic: KeyboardShortcutVisualizerKeyID,
        left: KeyboardShortcutVisualizerKeyID,
        right: KeyboardShortcutVisualizerKeyID,
        genericName: String,
        leftName: String,
        rightName: String
    ) {
        if pressedKeys.contains(generic) {
            parts.append(genericName)
        } else {
            if pressedKeys.contains(left) { parts.append(leftName) }
            if pressedKeys.contains(right) { parts.append(rightName) }
        }
    }

    private static func primaryKeyCode(from pressedKeys: Set<KeyboardShortcutVisualizerKeyID>) -> UInt16? {
        pressedKeys.compactMap { keyID -> UInt16? in
            if case let .keyCode(keyCode) = keyID {
                return keyCode
            }
            return nil
        }
        .sorted()
        .first
    }

    private static func keyDisplay(_ keyCode: UInt16) -> String {
        HotkeyDescriptor(keyCode: UInt32(keyCode), modifiers: []).display
    }

    private static func containsControl(in pressedKeys: Set<KeyboardShortcutVisualizerKeyID>) -> Bool {
        pressedKeys.contains(.genericControl)
            || pressedKeys.contains(.leftControl)
            || pressedKeys.contains(.rightControl)
    }

    private static func containsOption(in pressedKeys: Set<KeyboardShortcutVisualizerKeyID>) -> Bool {
        pressedKeys.contains(.genericOption)
            || pressedKeys.contains(.leftOption)
            || pressedKeys.contains(.rightOption)
    }

    private static func containsShift(in pressedKeys: Set<KeyboardShortcutVisualizerKeyID>) -> Bool {
        pressedKeys.contains(.genericShift)
            || pressedKeys.contains(.leftShift)
            || pressedKeys.contains(.rightShift)
    }

    private static func containsCommand(in pressedKeys: Set<KeyboardShortcutVisualizerKeyID>) -> Bool {
        pressedKeys.contains(.genericCommand)
            || pressedKeys.contains(.leftCommand)
            || pressedKeys.contains(.rightCommand)
    }

    private static func containsSideSpecificModifier(in pressedKeys: Set<KeyboardShortcutVisualizerKeyID>) -> Bool {
        pressedKeys.contains(.leftControl)
            || pressedKeys.contains(.rightControl)
            || pressedKeys.contains(.leftOption)
            || pressedKeys.contains(.rightOption)
            || pressedKeys.contains(.leftShift)
            || pressedKeys.contains(.rightShift)
            || pressedKeys.contains(.leftCommand)
            || pressedKeys.contains(.rightCommand)
    }
}
