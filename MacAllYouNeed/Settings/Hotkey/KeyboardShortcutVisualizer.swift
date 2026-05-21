import AppKit
import Carbon.HIToolbox
import Core
import Platform
import SwiftUI
import UI

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
