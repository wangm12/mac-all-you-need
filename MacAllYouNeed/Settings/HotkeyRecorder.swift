import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Platform
import SwiftUI

extension Notification.Name {
    static let hotkeyRecorderDidStartRecording = Notification.Name("MAYNHotkeyRecorderDidStartRecording")
    static let hotkeyRecorderDidStopRecording = Notification.Name("MAYNHotkeyRecorderDidStopRecording")
}

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

        let leftControl = rawFlags & 0x00000001 != 0
        let leftShift = rawFlags & 0x00000002 != 0
        let rightShift = rawFlags & 0x00000004 != 0
        let leftCommand = rawFlags & 0x00000008 != 0
        let rightCommand = rawFlags & 0x00000010 != 0
        let leftOption = rawFlags & 0x00000020 != 0
        let rightOption = rawFlags & 0x00000040 != 0
        let rightControl = rawFlags & 0x00002000 != 0

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

struct KeyboardShortcutRegistrationSummary: Equatable {
    let pressedText: String
    let registeredText: String
    let usesGenericRegistration: Bool
    let registrationNoticeText: String?

    init(state: KeyboardShortcutVisualizerState, candidate: HotkeyDescriptor? = nil) {
        let pressedKeys = state.pressedKeys
        pressedText = Self.physicalDisplay(from: pressedKeys)

        if let tap = candidate?.modifierTap {
            // Tap shortcut candidate — show the clean tap display ("Tap ⌘")
            // rather than the generic "⌘ + …" that implies a key press is needed.
            registeredText = HotkeyDescriptor(modifierTap: tap).display
            usesGenericRegistration = false
            registrationNoticeText = nil
        } else {
            registeredText = Self.registeredDisplay(from: pressedKeys)
            usesGenericRegistration = pressedText != registeredText
                && registeredText != Self.waitingForKeyText
            registrationNoticeText = Self.registrationNotice(from: pressedKeys)
        }
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

struct KeyboardShortcutVisualizerKey: Hashable {
    let ids: Set<KeyboardShortcutVisualizerKeyID>
    let label: String
    let widthUnits: CGFloat

    init(_ label: String, id: KeyboardShortcutVisualizerKeyID, widthUnits: CGFloat = 1) {
        self.ids = [id]
        self.label = label
        self.widthUnits = widthUnits
    }
}

enum KeyboardShortcutVisualizerPresentation {
    static let width: CGFloat = 700
    static let keyHeight: CGFloat = 37
    static let keySpacing: CGFloat = 6
    static let cornerRadius: CGFloat = MAYNControlMetrics.controlRadius
    static let respectsReduceMotion = true

    static let rows: [[KeyboardShortcutVisualizerKey]] = [
        [
            key("~", kVK_ANSI_Grave), key("1", kVK_ANSI_1), key("2", kVK_ANSI_2), key("3", kVK_ANSI_3),
            key("4", kVK_ANSI_4), key("5", kVK_ANSI_5), key("6", kVK_ANSI_6), key("7", kVK_ANSI_7),
            key("8", kVK_ANSI_8), key("9", kVK_ANSI_9), key("0", kVK_ANSI_0), key("-", kVK_ANSI_Minus),
            key("=", kVK_ANSI_Equal), key("delete", kVK_Delete, 1.5)
        ],
        [
            key("tab", kVK_Tab, 1.5), key("Q", kVK_ANSI_Q), key("W", kVK_ANSI_W), key("E", kVK_ANSI_E),
            key("R", kVK_ANSI_R), key("T", kVK_ANSI_T), key("Y", kVK_ANSI_Y), key("U", kVK_ANSI_U),
            key("I", kVK_ANSI_I), key("O", kVK_ANSI_O), key("P", kVK_ANSI_P), key("[", kVK_ANSI_LeftBracket),
            key("]", kVK_ANSI_RightBracket), key("\\", kVK_ANSI_Backslash, 1.1)
        ],
        [
            key("caps", kVK_CapsLock, 1.85), key("A", kVK_ANSI_A), key("S", kVK_ANSI_S), key("D", kVK_ANSI_D),
            key("F", kVK_ANSI_F), key("G", kVK_ANSI_G), key("H", kVK_ANSI_H), key("J", kVK_ANSI_J),
            key("K", kVK_ANSI_K), key("L", kVK_ANSI_L), key(";", kVK_ANSI_Semicolon),
            key("'", kVK_ANSI_Quote), key("return", kVK_Return, 1.95)
        ],
        [
            KeyboardShortcutVisualizerKey("⇧", id: .leftShift, widthUnits: 2.25),
            key("Z", kVK_ANSI_Z), key("X", kVK_ANSI_X), key("C", kVK_ANSI_C), key("V", kVK_ANSI_V),
            key("B", kVK_ANSI_B), key("N", kVK_ANSI_N), key("M", kVK_ANSI_M), key(",", kVK_ANSI_Comma),
            key(".", kVK_ANSI_Period), key("/", kVK_ANSI_Slash),
            KeyboardShortcutVisualizerKey("⇧", id: .rightShift, widthUnits: 2.25)
        ],
        [
            KeyboardShortcutVisualizerKey("fn", id: .fn),
            KeyboardShortcutVisualizerKey("⌃", id: .leftControl, widthUnits: 1.1),
            KeyboardShortcutVisualizerKey("⌥", id: .leftOption, widthUnits: 1.1),
            KeyboardShortcutVisualizerKey("⌘", id: .leftCommand, widthUnits: 1.35),
            key("", kVK_Space, 3.0),
            KeyboardShortcutVisualizerKey("⌘", id: .rightCommand, widthUnits: 1.35),
            KeyboardShortcutVisualizerKey("⌥", id: .rightOption, widthUnits: 1.1),
            KeyboardShortcutVisualizerKey("⌃", id: .rightControl, widthUnits: 1.1),
            key("←", kVK_LeftArrow),
            key("↑", kVK_UpArrow),
            key("↓", kVK_DownArrow),
            key("→", kVK_RightArrow)
        ]
    ]

    static func isPressed(_ key: KeyboardShortcutVisualizerKey, state: KeyboardShortcutVisualizerState) -> Bool {
        if !state.pressedKeys.isDisjoint(with: key.ids) {
            return true
        }
        return key.ids.contains { keyID in
            switch keyID {
            case .leftControl, .rightControl:
                state.pressedKeys.contains(.genericControl)
            case .leftOption, .rightOption:
                state.pressedKeys.contains(.genericOption)
            case .leftShift, .rightShift:
                state.pressedKeys.contains(.genericShift)
            case .leftCommand, .rightCommand:
                state.pressedKeys.contains(.genericCommand)
            default:
                false
            }
        }
    }

    private static func key(_ label: String, _ keyCode: Int, _ widthUnits: CGFloat = 1) -> KeyboardShortcutVisualizerKey {
        KeyboardShortcutVisualizerKey(label, id: .keyCode(UInt16(keyCode)), widthUnits: widthUnits)
    }
}

struct KeyboardShortcutVisualizer: View {
    let state: KeyboardShortcutVisualizerState
    let candidate: HotkeyDescriptor?
    let issueMessage: String?
    let onReset: () -> Void
    let onConfirm: () -> Void
    let onCancel: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        state: KeyboardShortcutVisualizerState,
        candidate: HotkeyDescriptor? = nil,
        issueMessage: String? = nil,
        onReset: @escaping () -> Void = {},
        onConfirm: @escaping () -> Void = {},
        onCancel: @escaping () -> Void = {}
    ) {
        self.state = state
        self.candidate = candidate
        self.issueMessage = issueMessage
        self.onReset = onReset
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(spacing: KeyboardShortcutVisualizerPresentation.keySpacing) {
            ForEach(Array(KeyboardShortcutVisualizerPresentation.rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: KeyboardShortcutVisualizerPresentation.keySpacing) {
                    ForEach(row, id: \.self) { key in
                        KeyboardShortcutKeyView(
                            key: key,
                            isPressed: KeyboardShortcutVisualizerPresentation.isPressed(key, state: state),
                            reduceMotion: reduceMotion
                        )
                    }
                }
            }
            KeyboardShortcutRegistrationSummaryView(
                summary: KeyboardShortcutRegistrationSummary(state: state, candidate: candidate),
                candidate: candidate,
                issueMessage: issueMessage,
                onReset: onReset,
                onConfirm: onConfirm,
                onCancel: onCancel
            )
            .padding(.top, 8)
        }
        .padding(14)
        .frame(width: KeyboardShortcutVisualizerPresentation.width)
        .background(MAYNTheme.elevated, in: RoundedRectangle(cornerRadius: MAYNControlMetrics.panelRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MAYNControlMetrics.panelRadius, style: .continuous)
                .stroke(MAYNTheme.subtleBorder, lineWidth: 1)
        )
        .accessibilityLabel("Keyboard shortcut preview")
    }
}

enum KeyboardShortcutConfirmationPresentation {
    static let resetTitle = "Reset"
    static let confirmTitle = "Confirm"
    static let cancelTitle = "Cancel"
    static let helpText = "Enter to confirm, Esc to cancel"
}

private struct KeyboardShortcutRegistrationSummaryView: View {
    let summary: KeyboardShortcutRegistrationSummary
    let candidate: HotkeyDescriptor?
    let issueMessage: String?
    let onReset: () -> Void
    let onConfirm: () -> Void
    let onCancel: () -> Void

    private var canConfirm: Bool {
        candidate != nil && issueMessage == nil
    }

    var body: some View {
        VStack(spacing: 7) {
            row(label: "Pressed", value: summary.pressedText)
            row(
                label: "Registers as",
                value: summary.registeredText,
                notice: summary.registrationNoticeText
            )
            if let issueMessage {
                Text(issueMessage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MAYNTheme.danger)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel(issueMessage)
            }
            if candidate != nil {
                HStack(spacing: 8) {
                    Text(KeyboardShortcutConfirmationPresentation.helpText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.80)
                    Spacer(minLength: 8)
                    MAYNButton(KeyboardShortcutConfirmationPresentation.resetTitle, height: 26, action: onReset)
                    MAYNButton(KeyboardShortcutConfirmationPresentation.cancelTitle, height: 26, action: onCancel)
                    MAYNButton(KeyboardShortcutConfirmationPresentation.confirmTitle, role: .primary, height: 26, action: onConfirm)
                        .disabled(!canConfirm)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(MAYNTheme.panel, in: RoundedRectangle(cornerRadius: MAYNControlMetrics.controlRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MAYNControlMetrics.controlRadius, style: .continuous)
                .stroke(summary.usesGenericRegistration ? Color.primary.opacity(0.22) : MAYNTheme.subtleBorder, lineWidth: 1)
        )
    }

    private func row(label: String, value: String, notice: String? = nil) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 92, alignment: .leading)
            Text(value)
                .font(.callout.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let notice {
                Text(notice)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.07), in: Capsule())
                    .overlay(Capsule().stroke(MAYNTheme.subtleBorder, lineWidth: 1))
            }
        }
    }
}

private struct KeyboardShortcutKeyView: View {
    let key: KeyboardShortcutVisualizerKey
    let isPressed: Bool
    let reduceMotion: Bool

    var body: some View {
        Text(key.label)
            .font(.system(size: key.label.count > 1 ? 11 : 14, weight: .medium, design: .rounded))
            .foregroundStyle(isPressed ? Color(nsColor: .controlBackgroundColor) : Color.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.65)
            .frame(
                width: key.widthUnits * KeyboardShortcutVisualizerPresentation.keyHeight,
                height: KeyboardShortcutVisualizerPresentation.keyHeight,
                alignment: .center
            )
            .background(
                isPressed ? Color.primary.opacity(0.72) : MAYNTheme.panel,
                in: RoundedRectangle(cornerRadius: KeyboardShortcutVisualizerPresentation.cornerRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: KeyboardShortcutVisualizerPresentation.cornerRadius, style: .continuous)
                    .stroke(isPressed ? Color.primary.opacity(0.32) : MAYNTheme.strongBorder, lineWidth: 1)
            )
            .scaleEffect(isPressed && !reduceMotion ? 0.94 : 1)
            .offset(y: isPressed && !reduceMotion ? 1 : 0)
            .animation(MAYNMotion.fastAnimation(reduceMotion: reduceMotion), value: isPressed)
    }
}

enum KeyboardShortcutFloatingOverlayPresentation {
    static let styleMask: NSWindow.StyleMask = [.borderless, .nonactivatingPanel]
    static let acceptsMouseEvents = true

    static func origin(panelSize: CGSize, visibleFrame: NSRect) -> NSPoint {
        NSPoint(
            x: visibleFrame.midX - panelSize.width / 2,
            y: visibleFrame.midY - panelSize.height / 2
        )
    }
}

final class KeyboardShortcutFloatingOverlayController {
    private var panel: NSPanel?
    private var hostingView: NSHostingView<KeyboardShortcutVisualizer>?
    private var presentationGeneration = 0

    deinit {
        panel?.orderOut(nil)
    }

    func update(
        state: KeyboardShortcutVisualizerState,
        candidate: HotkeyDescriptor? = nil,
        issueMessage: String? = nil,
        onReset: @escaping () -> Void = {},
        onConfirm: @escaping () -> Void = {},
        onCancel: @escaping () -> Void = {}
    ) {
        guard state.isRecording else {
            dismiss()
            return
        }
        show(
            state,
            candidate: candidate,
            issueMessage: issueMessage,
            onReset: onReset,
            onConfirm: onConfirm,
            onCancel: onCancel
        )
    }

    func owns(window: NSWindow?) -> Bool {
        guard let panel, let window else { return false }
        return panel === window
    }

    func dismiss(immediate: Bool = false) {
        guard let panel, panel.isVisible else { return }
        presentationGeneration += 1
        let generation = presentationGeneration
        guard !immediate else {
            panel.orderOut(nil)
            panel.alphaValue = 1
            return
        }

        let duration = MAYNMotionBridge.effectiveDuration(.toastOut)
        guard duration > 0 else {
            panel.orderOut(nil)
            panel.alphaValue = 1
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = MAYNMotionBridge.timingFunction(.toastOut)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            guard self?.presentationGeneration == generation else { return }
            panel.orderOut(nil)
            panel.alphaValue = 1
        }
    }

    private func show(
        _ state: KeyboardShortcutVisualizerState,
        candidate: HotkeyDescriptor?,
        issueMessage: String?,
        onReset: @escaping () -> Void,
        onConfirm: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        presentationGeneration += 1
        let panel = panel ?? makePanel()
        self.panel = panel
        let wasVisible = panel.isVisible
        let rootView = KeyboardShortcutVisualizer(
            state: state,
            candidate: candidate,
            issueMessage: issueMessage,
            onReset: onReset,
            onConfirm: onConfirm,
            onCancel: onCancel
        )

        let hostingView: NSHostingView<KeyboardShortcutVisualizer>
        if let existing = self.hostingView {
            existing.rootView = rootView
            hostingView = existing
        } else {
            let created = NSHostingView(rootView: rootView)
            created.autoresizingMask = [.width, .height]
            self.hostingView = created
            panel.contentView = created
            hostingView = created
        }

        hostingView.layoutSubtreeIfNeeded()
        var panelSize = hostingView.fittingSize
        panelSize.width = max(panelSize.width, KeyboardShortcutVisualizerPresentation.width)
        if panel.frame.size != panelSize {
            panel.setContentSize(panelSize)
            hostingView.frame = NSRect(origin: .zero, size: panelSize)
        }
        position(panel, panelSize: panelSize)

        if wasVisible { return }
        panel.alphaValue = 0
        FloatingHUDWindowLayering.orderFront(panel)

        let duration = MAYNMotionBridge.effectiveDuration(.toastIn)
        guard duration > 0 else {
            panel.alphaValue = 1
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = MAYNMotionBridge.timingFunction(.toastIn)
            panel.animator().alphaValue = 1
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(
                origin: .zero,
                size: CGSize(width: KeyboardShortcutVisualizerPresentation.width, height: 1)
            ),
            styleMask: KeyboardShortcutFloatingOverlayPresentation.styleMask,
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        FloatingHUDWindowLayering.configure(
            panel,
            acceptsMouseEvents: KeyboardShortcutFloatingOverlayPresentation.acceptsMouseEvents
        )
        return panel
    }

    private func position(_ panel: NSPanel, panelSize: CGSize) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let visibleFrame = screen?.visibleFrame else { return }
        panel.setFrameOrigin(
            KeyboardShortcutFloatingOverlayPresentation.origin(
                panelSize: panelSize,
                visibleFrame: visibleFrame
            )
        )
    }
}

struct HotkeyRecorder: NSViewRepresentable {
    @Binding var descriptor: HotkeyDescriptor
    @Binding private var visualizerState: KeyboardShortcutVisualizerState
    var isInvalid = false
    var candidateIssueMessage: (HotkeyDescriptor) -> String? = { _ in nil }
    /// Optional callback to override the chip's text. The floating keyboard
    /// popup still uses `descriptor.display` so the verbose form is preserved
    /// in the registration summary. Only the in-row chip changes.
    var chipDisplayOverride: ((HotkeyDescriptor) -> String)? = nil

    init(
        descriptor: Binding<HotkeyDescriptor>,
        isInvalid: Bool = false,
        visualizerState: Binding<KeyboardShortcutVisualizerState> = .constant(.inactive),
        candidateIssueMessage: @escaping (HotkeyDescriptor) -> String? = { _ in nil },
        chipDisplayOverride: ((HotkeyDescriptor) -> String)? = nil
    ) {
        _descriptor = descriptor
        _visualizerState = visualizerState
        self.isInvalid = isInvalid
        self.candidateIssueMessage = candidateIssueMessage
        self.chipDisplayOverride = chipDisplayOverride
    }

    func makeNSView(context: Context) -> RecorderView {
        RecorderView(
            descriptor: $descriptor,
            visualizerState: $visualizerState,
            isInvalid: isInvalid,
            candidateIssueMessage: candidateIssueMessage,
            chipDisplayOverride: chipDisplayOverride
        )
    }

    func updateNSView(_ nsView: RecorderView, context: Context) {
        nsView.updateDescriptorBinding($descriptor)
        nsView.updateVisualizerStateBinding($visualizerState)
        nsView.updateValidationState(isInvalid: isInvalid)
        nsView.updateCandidateIssueMessage(candidateIssueMessage)
        nsView.updateChipDisplayOverride(chipDisplayOverride)
    }

    final class RecorderView: NSView {
        @Binding var descriptor: HotkeyDescriptor
        @Binding var visualizerState: KeyboardShortcutVisualizerState
        private let label = NSTextField(labelWithString: "")
        private let floatingKeyboard = KeyboardShortcutFloatingOverlayController()
        private var isInvalid: Bool
        private var isRecording = false
        private var activeModifierFlags: NSEvent.ModifierFlags = []
        private var ignoreKeyEventsUntil: TimeInterval = 0
        private(set) var keyMonitor: Any?
        private var globalKeyMonitor: Any?
        private var eventTap: CFMachPort?
        private var eventTapSource: CFRunLoopSource?
        private var candidateIssueMessage: (HotkeyDescriptor) -> String?
        private var chipDisplayOverride: ((HotkeyDescriptor) -> String)?
        private(set) var pendingDescriptor: HotkeyDescriptor?
        private(set) var pendingIssueMessage: String?

        // Modifier-tap detection state
        private var tapPressTime: TimeInterval?
        private var tapPressCGFlags: CGEventFlags = []
        private var tapNonModifierPressed = false
        private var tapLastRelease: (key: ModifierTapShortcut.Key, time: TimeInterval, count: Int)?

        init(
            descriptor: Binding<HotkeyDescriptor>,
            visualizerState: Binding<KeyboardShortcutVisualizerState> = .constant(.inactive),
            isInvalid: Bool = false,
            candidateIssueMessage: @escaping (HotkeyDescriptor) -> String? = { _ in nil },
            chipDisplayOverride: ((HotkeyDescriptor) -> String)? = nil
        ) {
            _descriptor = descriptor
            _visualizerState = visualizerState
            self.isInvalid = isInvalid
            self.candidateIssueMessage = candidateIssueMessage
            self.chipDisplayOverride = chipDisplayOverride
            super.init(frame: .zero)
            label.alignment = .center
            label.lineBreakMode = .byTruncatingMiddle
            addSubview(label)
            wantsLayer = true
            layer?.borderWidth = 1
            setAccessibilityElement(true)
            setAccessibilityRole(.button)
            setAccessibilityLabel("Shortcut recorder")
            setLabelText(chipText(for: descriptor.wrappedValue))
            updateAppearance()
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { return nil }

        override var acceptsFirstResponder: Bool { true }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func layout() {
            super.layout()
            let labelBounds = bounds.insetBy(dx: 8, dy: 0)
            let labelHeight = min(label.intrinsicContentSize.height, labelBounds.height)
            label.frame = NSRect(
                x: labelBounds.minX,
                y: labelBounds.midY - labelHeight / 2,
                width: labelBounds.width,
                height: labelHeight
            )
        }

        override func mouseDown(with event: NSEvent) {
            startRecording(ignoreInitialKeyEvents: false)
        }

        override func accessibilityPerformPress() -> Bool {
            startRecording(ignoreInitialKeyEvents: true)
            return true
        }

        override func becomeFirstResponder() -> Bool {
            return true
        }

        override func resignFirstResponder() -> Bool {
            return true
        }

        override func keyDown(with event: NSEvent) {
            capture(event)
        }

        override func flagsChanged(with event: NSEvent) {
            updateActiveModifiers(event.modifierFlags)
        }

        override func viewDidChangeEffectiveAppearance() {
            super.viewDidChangeEffectiveAppearance()
            updateAppearance()
        }

        deinit {
            floatingKeyboard.dismiss(immediate: true)
            stopMonitoringKeyboard()
        }

        func updateDescriptorBinding(_ descriptor: Binding<HotkeyDescriptor>) {
            _descriptor = descriptor
            refresh()
        }

        func updateVisualizerStateBinding(_ visualizerState: Binding<KeyboardShortcutVisualizerState>) {
            _visualizerState = visualizerState
        }

        func updateValidationState(isInvalid: Bool) {
            self.isInvalid = isInvalid
            updateAppearance()
        }

        func updateCandidateIssueMessage(_ candidateIssueMessage: @escaping (HotkeyDescriptor) -> String?) {
            self.candidateIssueMessage = candidateIssueMessage
            if let pendingDescriptor {
                pendingIssueMessage = candidateIssueMessage(pendingDescriptor)
                refreshFloatingKeyboard()
            }
        }

        func updateChipDisplayOverride(_ override: ((HotkeyDescriptor) -> String)?) {
            self.chipDisplayOverride = override
            if !isRecording { setLabelText(chipText(for: descriptor)) }
        }

        private func chipText(for descriptor: HotkeyDescriptor) -> String {
            chipDisplayOverride?(descriptor) ?? descriptor.display
        }

        func refresh() {
            if !isRecording {
                setLabelText(chipText(for: descriptor))
            }
            updateAppearance()
        }

        private func startRecording(ignoreInitialKeyEvents: Bool) {
            guard !isRecording else { return }
            NSApp.activate(ignoringOtherApps: true)
            window?.makeKeyAndOrderFront(nil)
            window?.makeFirstResponder(self)
            activeModifierFlags = []
            pendingDescriptor = nil
            pendingIssueMessage = nil
            ignoreKeyEventsUntil = ignoreInitialKeyEvents ? ProcessInfo.processInfo.systemUptime + 0.15 : 0
            resetTapState()
            isRecording = true
            publishVisualizerState(.recording())
            setLabelText("Press shortcut...")
            startMonitoringKeyboard()
            NotificationCenter.default.post(name: .hotkeyRecorderDidStartRecording, object: self)
            updateAppearance()
        }

        private func stopRecording() {
            guard isRecording else { return }
            isRecording = false
            activeModifierFlags = []
            pendingDescriptor = nil
            pendingIssueMessage = nil
            ignoreKeyEventsUntil = 0
            resetTapState()
            publishVisualizerState(.inactive)
            stopMonitoringKeyboard()
            NotificationCenter.default.post(name: .hotkeyRecorderDidStopRecording, object: self)
            refresh()
        }

        private func capture(_ event: NSEvent) {
            guard isRecording else { return }
            let eventTime = event.timestamp > 0 ? event.timestamp : ProcessInfo.processInfo.systemUptime
            guard eventTime >= ignoreKeyEventsUntil else { return }
            if event.keyCode == 53 {
                stopRecording()
                return
            }
            // A real key is being pressed — cancel any pending tap candidate.
            tapNonModifierPressed = true
            if pendingDescriptor?.isModifierTap == true {
                pendingDescriptor = nil
                pendingIssueMessage = nil
            }
            if Self.isConfirmKey(event.keyCode), pendingDescriptor != nil {
                confirmPendingShortcut()
                return
            }
            let eventFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let captureFlags = eventFlags.isEmpty ? activeModifierFlags : eventFlags
            let raw = UInt32(captureFlags.rawValue)
            var mods: HotkeyDescriptor.Modifiers = []
            if raw & UInt32(NSEvent.ModifierFlags.command.rawValue) != 0 { mods.insert(.command) }
            if raw & UInt32(NSEvent.ModifierFlags.option.rawValue) != 0 { mods.insert(.option) }
            if raw & UInt32(NSEvent.ModifierFlags.control.rawValue) != 0 { mods.insert(.control) }
            if raw & UInt32(NSEvent.ModifierFlags.shift.rawValue) != 0 { mods.insert(.shift) }
            previewCandidate(
                HotkeyDescriptor(keyCode: UInt32(event.keyCode), modifiers: mods),
                state: .recording(keyCode: event.keyCode, modifierFlags: captureFlags)
            )
        }

        private func capture(keyCode: UInt16, cgFlags: CGEventFlags) {
            guard isRecording else { return }
            guard ProcessInfo.processInfo.systemUptime >= ignoreKeyEventsUntil else { return }
            if keyCode == 53 {
                stopRecording()
                return
            }
            // A real key is being pressed — cancel any pending tap candidate.
            tapNonModifierPressed = true
            if pendingDescriptor?.isModifierTap == true {
                pendingDescriptor = nil
                pendingIssueMessage = nil
            }
            if Self.isConfirmKey(keyCode), pendingDescriptor != nil {
                confirmPendingShortcut()
                return
            }
            previewCandidate(
                HotkeyRecorderEventTranslator.descriptor(
                    keyCode: keyCode,
                    cgFlags: cgFlags,
                    fallbackModifierFlags: activeModifierFlags
                ),
                state: .recording(keyCode: keyCode, cgFlags: cgFlags)
            )
        }

        func confirmPendingShortcut() {
            guard isRecording, let pendingDescriptor else { return }
            pendingIssueMessage = candidateIssueMessage(pendingDescriptor)
            refreshFloatingKeyboard()
            guard pendingIssueMessage == nil else {
                updateAppearance()
                return
            }

            descriptor = pendingDescriptor
            stopRecording()
        }

        func resetPendingShortcut() {
            guard isRecording else { return }
            activeModifierFlags = []
            pendingDescriptor = nil
            pendingIssueMessage = nil
            publishVisualizerState(.recording())
            setLabelText("Press shortcut...")
            updateAppearance()
        }

        private func previewCandidate(_ candidate: HotkeyDescriptor, state: KeyboardShortcutVisualizerState) {
            pendingDescriptor = candidate
            pendingIssueMessage = candidateIssueMessage(candidate)
            publishVisualizerState(state)
            setLabelText(chipText(for: candidate))
            updateAppearance()
        }

        private func updateActiveModifiers(_ flags: NSEvent.ModifierFlags) {
            activeModifierFlags = flags.intersection(.deviceIndependentFlagsMask)
            guard isRecording else { return }
            // If a new modifier press follows a tap candidate, drop the old
            // candidate so the new tap replaces it without needing Reset.
            if !activeModifierFlags.isEmpty && pendingDescriptor?.isModifierTap == true {
                pendingDescriptor = nil
                pendingIssueMessage = nil
            }
            guard pendingDescriptor == nil else {
                refreshFloatingKeyboard()
                return
            }
            pendingDescriptor = nil
            pendingIssueMessage = nil
            publishVisualizerState(.recording(modifierFlags: activeModifierFlags))
            let modifiers = modifierDisplay(from: activeModifierFlags)
            setLabelText(modifiers.isEmpty ? "Press shortcut..." : "\(modifiers)…")
        }

        private func updateActiveModifiers(cgFlags: CGEventFlags) {
            activeModifierFlags = HotkeyRecorderEventTranslator.modifierFlags(from: cgFlags)
            guard isRecording else { return }

            // Same as the NSEvent path: pressing a new modifier while a tap
            // candidate is pending should immediately clear that candidate so
            // the next release commits a fresh one. Keep `tapLastRelease`
            // intact — it's how a second tap of the same key becomes ×2.
            if !activeModifierFlags.isEmpty && pendingDescriptor?.isModifierTap == true {
                pendingDescriptor = nil
                pendingIssueMessage = nil
            }

            // Run tap detection when no combo shortcut is pending yet, OR when
            // a tap shortcut is pending (so the user can upgrade to double-tap).
            if pendingDescriptor == nil || pendingDescriptor?.isModifierTap == true {
                handleTapTransition(cgFlags: cgFlags)
            }

            // Refresh keyboard with current modifier state (always, so the
            // keyboard highlights the held keys live).
            let recorderState = KeyboardShortcutVisualizerState.recording(cgFlags: cgFlags)
            visualizerState = recorderState
            floatingKeyboard.update(
                state: recorderState,
                candidate: pendingDescriptor ?? Self.placeholderCandidate,
                issueMessage: pendingDescriptor?.isModifierTap == true ? nil : pendingIssueMessage,
                onReset: { [weak self] in self?.resetPendingShortcut() },
                onConfirm: { [weak self] in self?.confirmPendingShortcut() },
                onCancel: { [weak self] in self?.stopRecording() }
            )

            guard pendingDescriptor == nil else { return }

            let modifiers = modifierDisplay(from: activeModifierFlags)
            setLabelText(modifiers.isEmpty ? "Press shortcut..." : "\(modifiers)…")
        }

        private func publishVisualizerState(_ state: KeyboardShortcutVisualizerState) {
            visualizerState = state
            floatingKeyboard.update(
                state: state,
                candidate: pendingDescriptor ?? Self.placeholderCandidate,
                issueMessage: pendingIssueMessage,
                onReset: { [weak self] in
                    self?.resetPendingShortcut()
                },
                onConfirm: { [weak self] in
                    self?.confirmPendingShortcut()
                },
                onCancel: { [weak self] in
                    self?.stopRecording()
                }
            )
        }

        private func refreshFloatingKeyboard() {
            floatingKeyboard.update(
                state: visualizerState,
                candidate: pendingDescriptor ?? Self.placeholderCandidate,
                issueMessage: pendingIssueMessage,
                onReset: { [weak self] in
                    self?.resetPendingShortcut()
                },
                onConfirm: { [weak self] in
                    self?.confirmPendingShortcut()
                },
                onCancel: { [weak self] in
                    self?.stopRecording()
                }
            )
        }

        private func modifierDisplay(from flags: NSEvent.ModifierFlags) -> String {
            var s = ""
            if flags.contains(.control) { s += "⌃" }
            if flags.contains(.option) { s += "⌥" }
            if flags.contains(.shift) { s += "⇧" }
            if flags.contains(.command) { s += "⌘" }
            return s
        }

        private static func isConfirmKey(_ keyCode: UInt16) -> Bool {
            Int(keyCode) == kVK_Return || Int(keyCode) == kVK_ANSI_KeypadEnter
        }

        /// Placeholder candidate used to keep the Confirm / Reset / Cancel
        /// button row visible in the floating keyboard even before the user
        /// has held a valid shortcut. Clicking Confirm with this placeholder
        /// is a safe no-op because `confirmPendingShortcut` guards on the
        /// real `pendingDescriptor`.
        private static let placeholderCandidate = HotkeyDescriptor(keyCode: 0, modifiers: [])

        // MARK: - Modifier-tap detection

        private func handleTapTransition(cgFlags: CGEventFlags) {
            let now = ProcessInfo.processInfo.systemUptime
            let held = !activeModifierFlags.isEmpty

            if held {
                if tapPressTime == nil {
                    tapPressTime = now
                    tapNonModifierPressed = false
                }
                tapPressCGFlags = cgFlags
            } else if tapPressTime != nil {
                tapPressTime = nil
                // No hold-time limit in the recorder: the user is *picking*
                // a modifier, not demonstrating real tap timing. We only
                // reject if a non-modifier key was pressed during the hold
                // (that turns the press into a combo capture, not a tap).
                // The runtime dispatcher (ModifierTapDispatcher) still enforces
                // its own tap-hold limit so accidental long-holds at use time
                // don't trigger the shortcut.
                guard !tapNonModifierPressed else {
                    tapNonModifierPressed = false
                    tapLastRelease = nil
                    return
                }
                tapNonModifierPressed = false
                guard let key = tapKeyFromCGFlags(tapPressCGFlags) else { return }
                let count: Int
                if let last = tapLastRelease, last.key == key, now - last.time <= 0.28 {
                    count = min(last.count + 1, 2)
                } else {
                    count = 1
                }
                tapLastRelease = (key: key, time: now, count: count)
                let tapDescriptor = HotkeyDescriptor(modifierTap: ModifierTapShortcut(key: key, count: count))
                // Use the NSEvent modifierFlags path so the keyboard visualizer
                // shows the generic modifier key (e.g. "⌘") rather than defaulting
                // to "Left ⌘" when physical device bits are unavailable.
                previewCandidate(tapDescriptor, state: .recording(modifierFlags: activeModifierFlags))
            }
        }

        private func tapKeyFromCGFlags(_ cgFlags: CGEventFlags) -> ModifierTapShortcut.Key? {
            let raw = cgFlags.rawValue
            let lCtrl  = raw & 0x00000001 != 0
            let lShift = raw & 0x00000002 != 0
            let rShift = raw & 0x00000004 != 0
            let lCmd   = raw & 0x00000008 != 0
            let rCmd   = raw & 0x00000010 != 0
            let lOpt   = raw & 0x00000020 != 0
            let rOpt   = raw & 0x00000040 != 0
            let rCtrl  = raw & 0x00002000 != 0
            var families = 0
            var result: ModifierTapShortcut.Key?
            if lCtrl || rCtrl || cgFlags.contains(.maskControl) {
                families += 1
                result = lCtrl && !rCtrl ? .leftControl : rCtrl && !lCtrl ? .rightControl : .control
            }
            if lOpt || rOpt || cgFlags.contains(.maskAlternate) {
                families += 1
                result = lOpt && !rOpt ? .leftOption : rOpt && !lOpt ? .rightOption : .option
            }
            if lCmd || rCmd || cgFlags.contains(.maskCommand) {
                families += 1
                result = lCmd && !rCmd ? .leftCommand : rCmd && !lCmd ? .rightCommand : .command
            }
            if lShift || rShift || cgFlags.contains(.maskShift) {
                families += 1
                result = lShift && !rShift ? .leftShift : rShift && !lShift ? .rightShift : .shift
            }
            if cgFlags.contains(.maskSecondaryFn) { families += 1; result = .fn }
            return families == 1 ? result : nil
        }

        private func resetTapState() {
            tapPressTime = nil
            tapPressCGFlags = []
            tapNonModifierPressed = false
            tapLastRelease = nil
        }

        private func startMonitoringKeyboard() {
            guard keyMonitor == nil else { return }
            startKeyboardEventTap()
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged, .leftMouseDown]) { [weak self] event in
                guard let self, self.isRecording else { return event }
                if event.type == .leftMouseDown {
                    if self.floatingKeyboard.owns(window: event.window) {
                        return event
                    }
                    if event.window !== self.window || !self.bounds.contains(self.convert(event.locationInWindow, from: nil)) {
                        self.stopRecording()
                    }
                    return event
                }
                if event.type == .flagsChanged {
                    self.updateActiveModifiers(event.modifierFlags)
                    return nil
                }
                self.capture(event)
                return nil
            }
            globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
                DispatchQueue.main.async {
                    guard let self, self.isRecording else { return }
                    if event.type == .flagsChanged {
                        self.updateActiveModifiers(event.modifierFlags)
                    } else {
                        self.capture(event)
                    }
                }
            }
        }

        private func stopMonitoringKeyboard() {
            stopKeyboardEventTap()
            if let keyMonitor {
                NSEvent.removeMonitor(keyMonitor)
                self.keyMonitor = nil
            }
            if let globalKeyMonitor {
                NSEvent.removeMonitor(globalKeyMonitor)
                self.globalKeyMonitor = nil
            }
        }

        private func startKeyboardEventTap() {
            guard eventTap == nil else { return }
            let mask = CGEventMask(
                (1 << CGEventType.keyDown.rawValue)
                    | (1 << CGEventType.flagsChanged.rawValue)
                    | (1 << CGEventType.tapDisabledByTimeout.rawValue)
                    | (1 << CGEventType.tapDisabledByUserInput.rawValue)
            )
            let userInfo = Unmanaged.passUnretained(self).toOpaque()
            guard let tap = CGEvent.tapCreate(
                tap: .cghidEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: { _, type, event, userInfo in
                    guard let userInfo else { return Unmanaged.passUnretained(event) }
                    let recorder = Unmanaged<RecorderView>.fromOpaque(userInfo).takeUnretainedValue()
                    return recorder.handleKeyboardEventTap(type: type, event: event)
                },
                userInfo: userInfo
            ) else {
                return
            }

            eventTap = tap
            eventTapSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            if let eventTapSource {
                CFRunLoopAddSource(CFRunLoopGetMain(), eventTapSource, .commonModes)
            }
            CGEvent.tapEnable(tap: tap, enable: true)
        }

        private func stopKeyboardEventTap() {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: false)
            }
            if let eventTapSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), eventTapSource, .commonModes)
            }
            eventTapSource = nil
            eventTap = nil
        }

        private func handleKeyboardEventTap(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let eventTap {
                    CGEvent.tapEnable(tap: eventTap, enable: true)
                }
                return Unmanaged.passUnretained(event)
            }

            guard isRecording else {
                return Unmanaged.passUnretained(event)
            }

            switch type {
            case .flagsChanged:
                updateActiveModifiers(cgFlags: event.flags)
                return nil
            case .keyDown:
                capture(
                    keyCode: UInt16(event.getIntegerValueField(.keyboardEventKeycode)),
                    cgFlags: event.flags
                )
                return nil
            default:
                return Unmanaged.passUnretained(event)
            }
        }

        private func updateAppearance() {
            layer?.cornerRadius = HotkeyChipPresentation.cornerRadius
            layer?.backgroundColor = resolvedColor(.textBackgroundColor)
            let borderColor: NSColor
            if isInvalid {
                borderColor = .systemRed
            } else if isRecording {
                layer?.borderColor = neutralLayerColor(alpha: 0.34)
                setLabelText(label.stringValue)
                return
            } else {
                layer?.borderColor = neutralLayerColor(alpha: 0.14)
                setLabelText(label.stringValue)
                return
            }
            layer?.borderColor = resolvedColor(borderColor)
            setLabelText(label.stringValue)
        }

        private func setLabelText(_ text: String) {
            label.attributedStringValue = HotkeyChipPresentation.attributedString(
                text,
                color: isRecording ? .labelColor : .labelColor,
                compact: bounds.height <= HotkeyChipPresentation.compactHeight
            )
            needsLayout = true
        }

        private func resolvedColor(_ color: NSColor) -> CGColor {
            var result: CGColor = NSColor(calibratedRed: 1, green: 0.25, blue: 0.22, alpha: 1).cgColor
            effectiveAppearance.performAsCurrentDrawingAppearance {
                result = color.usingColorSpace(.deviceRGB)?.cgColor ?? result
            }
            return result
        }

        private func neutralLayerColor(alpha: CGFloat) -> CGColor {
            let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(calibratedWhite: isDark ? 1 : 0, alpha: alpha).cgColor
        }
    }
}

enum HotkeyRecorderControlAxisAlignment: Equatable {
    case trailing
}

enum HotkeyRecorderErrorPlacement: Equatable {
    case belowControlsRightAligned
}

enum HotkeyRecorderResetState: Equatable {
    case active
    case inactive
}

struct HotkeyRecorderControlLayout: Equatable {
    let containerWidth: CGFloat
    let controlsAlignment: HotkeyRecorderControlAxisAlignment
    let errorPlacement: HotkeyRecorderErrorPlacement
}

enum HotkeyRecorderControlPresentation {
    static let defaultRecorderHeight = HotkeyChipPresentation.compactHeight

    static func layout(
        recorderWidth: CGFloat,
        resetWidth: CGFloat,
        spacing: CGFloat,
        errorWidth: CGFloat,
        visualizerWidth: CGFloat = 0,
        isRecording: Bool = false
    ) -> HotkeyRecorderControlLayout {
        HotkeyRecorderControlLayout(
            containerWidth: max(errorWidth, recorderWidth + spacing + resetWidth),
            controlsAlignment: .trailing,
            errorPlacement: .belowControlsRightAligned
        )
    }

    static func resetState(
        descriptor: HotkeyDescriptor,
        defaultDescriptor: HotkeyDescriptor?
    ) -> HotkeyRecorderResetState {
        guard let defaultDescriptor else { return .active }
        return descriptor == defaultDescriptor ? .inactive : .active
    }

    static func rowIssueMessage(
        validationIssue: String?,
        registrationErrors: [HotkeyAction: String],
        action: HotkeyAction
    ) -> String? {
        validationIssue ?? registrationErrors[action]
    }

    static func registrationErrors(
        from error: Error,
        changedAction: HotkeyAction
    ) -> [HotkeyAction: String] {
        if case let HotkeyRegistryError.registrationFailed(action, _) = error {
            return [action: error.localizedDescription]
        }
        return [changedAction: error.localizedDescription]
    }
}

struct HotkeyRecorderControl: View {
    @Binding var descriptor: HotkeyDescriptor
    @State private var visualizerState = KeyboardShortcutVisualizerState.inactive
    var issueMessage: String?
    var candidateIssueMessage: (HotkeyDescriptor) -> String? = { _ in nil }
    var defaultDescriptor: HotkeyDescriptor?
    var recorderWidth: CGFloat = 112
    var recorderHeight: CGFloat = HotkeyRecorderControlPresentation.defaultRecorderHeight
    var resetWidth: CGFloat = 64
    var errorWidth: CGFloat = 220
    var alignment: HorizontalAlignment = .trailing
    var errorFrameAlignment: Alignment = .trailing
    var chipDisplayOverride: ((HotkeyDescriptor) -> String)? = nil
    let reset: () -> Void

    var body: some View {
        let layout = HotkeyRecorderControlPresentation.layout(
            recorderWidth: recorderWidth,
            resetWidth: resetWidth,
            spacing: 8,
            errorWidth: errorWidth,
            visualizerWidth: KeyboardShortcutVisualizerPresentation.width,
            isRecording: visualizerState.isRecording
        )
        let resetState = HotkeyRecorderControlPresentation.resetState(
            descriptor: descriptor,
            defaultDescriptor: defaultDescriptor
        )

        VStack(alignment: alignment, spacing: 5) {
            HStack(spacing: 8) {
                HotkeyRecorder(
                    descriptor: $descriptor,
                    isInvalid: issueMessage != nil,
                    visualizerState: $visualizerState,
                    candidateIssueMessage: candidateIssueMessage,
                    chipDisplayOverride: chipDisplayOverride
                )
                    .frame(width: recorderWidth, height: recorderHeight)
                Button(action: reset) {
                    Text("Reset")
                        .font(.callout.weight(resetState == .active ? .medium : .regular))
                        .foregroundStyle(resetState == .active ? .primary : .secondary)
                        .frame(width: resetWidth, height: recorderHeight)
                        .background(resetBackground(for: resetState), in: RoundedRectangle(cornerRadius: HotkeyChipPresentation.cornerRadius, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: HotkeyChipPresentation.cornerRadius, style: .continuous)
                                .stroke(resetBorder(for: resetState), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .disabled(resetState == .inactive)
                .opacity(resetState == .active ? 1 : 0.62)
            }
            .frame(width: layout.containerWidth, alignment: .trailing)

            if let issueMessage {
                Text(issueMessage)
                    .font(.caption)
                    .foregroundStyle(MAYNTheme.danger)
                    .multilineTextAlignment(.trailing)
                    .frame(width: layout.containerWidth, alignment: errorFrameAlignment)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(width: layout.containerWidth, alignment: .trailing)
    }

    private func resetBackground(for state: HotkeyRecorderResetState) -> Color {
        switch state {
        case .active:
            MAYNTheme.elevated
        case .inactive:
            MAYNTheme.elevated
        }
    }

    private func resetBorder(for state: HotkeyRecorderResetState) -> Color {
        switch state {
        case .active:
            MAYNTheme.strongBorder
        case .inactive:
            .clear
        }
    }
}

enum HotkeyRecorderEventTranslator {
    static func descriptor(
        keyCode: UInt16,
        cgFlags: CGEventFlags,
        fallbackModifierFlags: NSEvent.ModifierFlags
    ) -> HotkeyDescriptor {
        let modifierFlags = modifierFlags(from: cgFlags)
        let captureFlags = modifierFlags.isEmpty ? fallbackModifierFlags : modifierFlags
        return HotkeyDescriptor(
            keyCode: UInt32(keyCode),
            modifiers: modifiers(from: captureFlags)
        )
    }

    static func modifierFlags(from cgFlags: CGEventFlags) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if cgFlags.contains(.maskCommand) { flags.insert(.command) }
        if cgFlags.contains(.maskAlternate) { flags.insert(.option) }
        if cgFlags.contains(.maskControl) { flags.insert(.control) }
        if cgFlags.contains(.maskShift) { flags.insert(.shift) }
        return flags
    }

    private static func modifiers(from flags: NSEvent.ModifierFlags) -> HotkeyDescriptor.Modifiers {
        var modifiers: HotkeyDescriptor.Modifiers = []
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        return modifiers
    }
}
