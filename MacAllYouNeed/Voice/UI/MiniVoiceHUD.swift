import AppKit
import SwiftUI

@MainActor
final class MiniVoiceHUD {
    enum State: Equatable {
        case idlePreview
        case recording(level: Float)
        case transcribing
        case pasted
        case noSpeech(String)
        case error(String)
    }

    private var panel: NSPanel?
    private var hostingView: FirstMouseHostingView<MiniVoiceHUDView>?

    #if DEBUG
    var testingContentView: NSView? {
        panel?.contentView
    }
    #endif

    func show(
        _ state: State,
        onCancel: (() -> Void)? = nil,
        onPrimary: (() -> Void)? = nil
    ) {
        let panel = panel ?? makePanel()
        self.panel = panel
        let wasVisible = panel.isVisible
        let previousSize = panel.frame.size
        let nextSize = MiniVoiceHUDLayout.size(for: state)
        let nextView = MiniVoiceHUDView(
            state: state,
            onCancel: onCancel,
            onPrimary: onPrimary
        )
        if let hostingView {
            hostingView.rootView = nextView
        } else {
            let hostingView = FirstMouseHostingView(rootView: nextView)
            self.hostingView = hostingView
            panel.contentView = hostingView
        }
        if previousSize != nextSize {
            panel.setContentSize(nextSize)
        }
        if !wasVisible || previousSize != nextSize {
            position(panel)
        }
        if !wasVisible {
            panel.alphaValue = 0
        }
        if wasVisible { return }

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

    func dismiss() {
        guard let panel, panel.isVisible else { return }

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
        } completionHandler: {
            panel.orderOut(nil)
            panel.alphaValue = 1
        }
    }

    private func makePanel() -> NSPanel {
        let panel = VoiceHUDPanel(
            contentRect: NSRect(origin: .zero, size: MiniVoiceHUDLayout.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.hasShadow = false
        panel.backgroundColor = .clear
        FloatingHUDWindowLayering.configure(panel, acceptsMouseEvents: true)
        return panel
    }

    private func position(_ panel: NSPanel) {
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let frame = screen?.visibleFrame else { return }
        panel.setFrameOrigin(NSPoint(
            x: frame.midX - panel.frame.width / 2,
            y: frame.minY + 96
        ))
    }
}

enum MiniVoiceHUDLayout {
    static let panelSize = CGSize(width: 132, height: 78)
    static let tipWidth: CGFloat = 112
    static let tipHeight: CGFloat = 30
    static let controlWidth: CGFloat = 128
    static let controlHeight: CGFloat = 42
    static let buttonSize: CGFloat = 34
    static let waveformWidth: CGFloat = 40
    static let waveformHeight: CGFloat = 20

    static func size(for state: MiniVoiceHUD.State) -> CGSize {
        MiniVoiceHUDPresentationState(state: state).tipTitle == nil
            ? CGSize(width: controlWidth, height: controlHeight)
            : panelSize
    }
}

struct MiniVoiceHUDActionState: Equatable {
    let cancelEnabled: Bool
    let primaryEnabled: Bool
    let primarySymbol: String
    let primaryAccessibilityLabel: String

    init(state: MiniVoiceHUD.State) {
        switch state.displayState {
        case .idlePreview:
            cancelEnabled = false
            primaryEnabled = false
            primarySymbol = "stop.fill"
            primaryAccessibilityLabel = "Ready"
        case .recording:
            cancelEnabled = true
            primaryEnabled = true
            primarySymbol = "stop.fill"
            primaryAccessibilityLabel = "Stop and transcribe"
        case .transcribing:
            cancelEnabled = true
            primaryEnabled = false
            primarySymbol = "hourglass"
            primaryAccessibilityLabel = "Transcribing"
        case .pasted:
            cancelEnabled = false
            primaryEnabled = true
            primarySymbol = "checkmark"
            primaryAccessibilityLabel = "Dismiss"
        case .noSpeech:
            cancelEnabled = false
            primaryEnabled = true
            primarySymbol = "ellipsis"
            primaryAccessibilityLabel = "Dismiss"
        case .error:
            cancelEnabled = false
            primaryEnabled = true
            primarySymbol = "exclamationmark"
            primaryAccessibilityLabel = "Dismiss"
        }
    }
}

struct MiniVoiceHUDPresentationState: Equatable {
    let tipTitle: String?

    init(state: MiniVoiceHUD.State) {
        switch state.displayState {
        case .idlePreview, .recording:
            tipTitle = nil
        case .transcribing, .pasted, .noSpeech, .error:
            tipTitle = nil
        }
    }
}

private extension MiniVoiceHUD.State {
    var displayState: MiniVoiceHUD.State {
        if case let .error(message) = self,
           message.localizedCaseInsensitiveContains("no usable audio")
           || message.localizedCaseInsensitiveContains("transcript was empty")
        {
            return .noSpeech(message)
        }
        return self
    }
}

private struct MiniVoiceHUDView: View {
    let state: MiniVoiceHUD.State
    let onCancel: (() -> Void)?
    let onPrimary: (() -> Void)?

    var body: some View {
        VStack(spacing: 6) {
            if let tipTitle = presentation.tipTitle {
                Text(tipTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .frame(width: MiniVoiceHUDLayout.tipWidth, height: MiniVoiceHUDLayout.tipHeight)
                    .background(Color.black, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }

            HStack(spacing: 7) {
                HUDCircleButton(
                    symbol: "xmark",
                    accessibilityLabel: "Cancel voice dictation",
                    isEnabled: actionState.cancelEnabled,
                    style: .secondary,
                    action: onCancel
                )

                VoiceWaveform(level: recordingLevel, phase: phase)
                    .frame(width: MiniVoiceHUDLayout.waveformWidth, height: MiniVoiceHUDLayout.waveformHeight)

                HUDCircleButton(
                    symbol: actionState.primarySymbol,
                    accessibilityLabel: actionState.primaryAccessibilityLabel,
                    isEnabled: actionState.primaryEnabled,
                    style: .primary,
                    action: onPrimary
                )
            }
            .frame(width: MiniVoiceHUDLayout.controlWidth, height: MiniVoiceHUDLayout.controlHeight)
            .background(Color.black, in: Capsule())
        }
        .frame(
            width: MiniVoiceHUDLayout.size(for: state).width,
            height: MiniVoiceHUDLayout.size(for: state).height
        )
    }

    private var actionState: MiniVoiceHUDActionState {
        MiniVoiceHUDActionState(state: state)
    }

    private var presentation: MiniVoiceHUDPresentationState {
        MiniVoiceHUDPresentationState(state: state)
    }

    private var phase: VoiceWaveform.Phase {
        switch visualState {
        case .idlePreview: .idle
        case .recording: .recording
        case .transcribing: .transcribing
        case .pasted: .complete
        case .noSpeech: .flat
        case .error: .error
        }
    }

    private var recordingLevel: Float {
        switch state {
        case let .recording(level):
            level
        default:
            0
        }
    }

    private var visualState: MiniVoiceHUD.State {
        state.displayState
    }
}

private struct HUDCircleButton: View {
    enum Style {
        case primary
        case secondary
    }

    let symbol: String
    let accessibilityLabel: String
    let isEnabled: Bool
    let style: Style
    let action: (() -> Void)?

    var body: some View {
        Button {
            action?()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(foreground)
                .frame(width: MiniVoiceHUDLayout.buttonSize, height: MiniVoiceHUDLayout.buttonSize)
                .background(background, in: Circle())
                .overlay(Circle().stroke(stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || action == nil)
        .accessibilityLabel(accessibilityLabel)
    }

    private var foreground: Color {
        switch style {
        case .primary:
            isEnabled ? .black : .white.opacity(0.36)
        case .secondary:
            .white.opacity(isEnabled ? 0.92 : 0.42)
        }
    }

    private var background: Color {
        switch style {
        case .primary:
            isEnabled ? .white : .white.opacity(0.08)
        case .secondary:
            .white.opacity(isEnabled ? 0.14 : 0.07)
        }
    }

    private var stroke: Color {
        switch style {
        case .primary:
            isEnabled ? .white.opacity(0.88) : .white.opacity(0.10)
        case .secondary:
            .white.opacity(0.10)
        }
    }
}

private struct VoiceWaveform: View {
    enum Phase {
        case idle
        case recording
        case transcribing
        case complete
        case flat
        case error
    }

    let level: Float
    let phase: Phase

    private let base: [CGFloat] = [0.34, 0.58, 0.42, 0.78, 0.50, 0.90, 0.62, 0.44, 0.70, 0.36]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(base.indices, id: \.self) { index in
                Capsule()
                    .fill(barColor)
                    .frame(width: 2, height: barHeight(index))
                    .animation(.easeOut(duration: 0.06), value: barHeight(index))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var barColor: Color {
        switch phase {
        case .error:
            Color.white.opacity(0.48)
        case .flat:
            Color.white.opacity(0.32)
        default:
            Color.white.opacity(0.82)
        }
    }

    private func barHeight(_ index: Int) -> CGFloat {
        switch phase {
        case .idle:
            return 5 + base[index] * 5
        case .recording:
            let scaled = CGFloat(min(max(level * 3, 0.12), 1))
            return 5 + base[index] * 17 * scaled
        case .transcribing:
            return 6 + base.reversed()[index] * 14
        case .complete:
            return 12
        case .flat:
            return 4
        case .error:
            return index.isMultiple(of: 2) ? 6 : 12
        }
    }
}

/// NSPanel subclass for the voice HUD — plain NSPanel is fine since we fix
/// first-click on the content view level instead.
private typealias VoiceHUDPanel = NSPanel

/// NSHostingView subclass that reports acceptsFirstMouse = true so SwiftUI
/// buttons in the floating HUD respond on the first click without requiring
/// the panel to become key first.
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
        true
    }
}
