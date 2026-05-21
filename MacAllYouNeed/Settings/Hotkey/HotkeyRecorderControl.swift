import Core
import Platform
import SwiftUI
import UI

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
