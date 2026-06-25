import Core
import Platform
import SwiftUI

struct VoiceHotkeyStepView: View {
    let controller: AppController
    @State private var shortcut: Platform.HotkeyDescriptor
    @State private var mode: VoiceActivationMode
    @State private var hybridThresholdMs = 500.0
    @State private var statusMessage: String?
    @State private var shortcutIssueMessage: String?
    @State private var showsHUDPreview = false

    init(controller: AppController) {
        self.controller = controller
        let settings = VoiceActivationSettingsStore.load()
        _shortcut = State(initialValue: settings.shortcut)
        _mode = State(initialValue: settings.mode)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Set your voice shortcut")
                .font(.title)
                .bold()
            Text(
                "Default is \(VoiceActivationSettings.default.shortcut.display). "
                    + "Fn / Globe is optional because it can conflict with input switching."
            )
            .foregroundStyle(.secondary)
            VoiceKeyboardPreview(shortcutDisplay: shortcut.display)
            HStack {
                Text("Shortcut")
                Spacer()
                HotkeyRecorderControl(
                    descriptor: shortcutBinding,
                    issueMessage: shortcutIssueMessage,
                    candidateIssueMessage: { shortcutCandidateIssueMessage($0) },
                    defaultDescriptor: VoiceActivationSettings.default.shortcut,
                    recorderWidth: 140,
                    recorderHeight: 26,
                    errorWidth: 220,
                    alignment: .trailing,
                    errorFrameAlignment: .trailing,
                    reset: { applyShortcut(VoiceActivationSettings.default.shortcut) }
                )
            }
            VoiceActivationModePicker(mode: activationModeBinding)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Hybrid threshold")
                    Slider(value: $hybridThresholdMs, in: 200 ... 1200, step: 50)
                    Text("\(Int(hybridThresholdMs))ms")
                        .monospacedDigit()
                }
                .disabled(true)
                Text("Hybrid and Auto-VAD are shown here so you can review the available activation modes before finishing setup.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                MAYNButton("Test now") {
                    showsHUDPreview = true
                    statusMessage = "HUD preview only. Recording will not start from this button."
                }
            }
            if showsHUDPreview {
                VoiceHUDPreview()
            }
            if let statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var shortcutBinding: Binding<Platform.HotkeyDescriptor> {
        Binding(
            get: { shortcut },
            set: { descriptor in
                applyShortcut(descriptor)
            }
        )
    }

    private var activationModeBinding: Binding<VoiceActivationMode> {
        Binding(
            get: { mode },
            set: { newMode in
                mode = newMode
                applySettingsIfValid()
            }
        )
    }

    private func applyShortcut(_ descriptor: Platform.HotkeyDescriptor) {
        shortcut = descriptor
        applySettingsIfValid()
    }

    private func shortcutCandidateIssueMessage(_ descriptor: Platform.HotkeyDescriptor) -> String? {
        HotkeyValidation.issue(
            forVoiceShortcut: descriptor,
            appHotkeys: HotkeyMapStore.load(),
            dockShortcuts: HotkeyValidation.liveDockShortcuts()
        )?.message
    }

    private func applySettingsIfValid() {
        if let issue = HotkeyValidation.issue(
            forVoiceShortcut: shortcut,
            appHotkeys: HotkeyMapStore.load(),
            dockShortcuts: HotkeyValidation.liveDockShortcuts()
        ) {
            shortcutIssueMessage = issue.message
            statusMessage = issue.message
            return
        }

        do {
            try controller.applyVoiceActivationSettings(VoiceActivationSettings(shortcut: shortcut, mode: mode))
            shortcutIssueMessage = nil
            statusMessage = "Voice shortcut saved."
        } catch {
            shortcutIssueMessage = error.localizedDescription
            statusMessage = error.localizedDescription
        }
    }
}

struct VoiceKeyboardPreview: View {
    let shortcutDisplay: String

    var body: some View {
        HStack(spacing: 6) {
            ShortcutChip(text: shortcutDisplay, height: 34)
            Text("Current shortcut")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 8)
        }
    }
}

struct VoiceActivationModePicker: View {
    @Binding var mode: VoiceActivationMode

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Activation mode")
                .font(.headline)
            FunctionSegmentedTabStrip(
                tabs: Array(VoiceActivationMode.allCases),
                selection: mode,
                fillsAvailableWidth: true,
                size: .control
            ) { nextMode in
                mode = nextMode
            }
            HStack(spacing: 10) {
                Label("Hybrid", systemImage: "clock")
                Label("Auto-VAD", systemImage: "waveform")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

struct VoiceHUDPreview: View {
    @StateObject private var thinkingProgress = MiniVoiceThinkingProgressBridge()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var state: MiniVoiceHUD.State = .recording(level: 0.45)
    @State private var phaseIndex = 0
    private let phaseTimer = Timer.publish(every: 0.9, on: .main, in: .common).autoconnect()

    private var sequence: [MiniVoiceHUD.State] {
        [
            .recording(level: 0.45),
            .transcribing(.finalizing),
            .transcribing(.asr),
            .transcribing(.cleanup(progress: 0.35)),
            .transcribing(.cleanup(progress: 0.72)),
            .transcribing(.pasting),
            .cancelled
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            MiniVoiceHUDView(
                state: state,
                chrome: .init(),
                pill: MiniVoiceHUDPill(state: state),
                thinkingProgress: thinkingProgress,
                audioLevel: MiniVoiceAudioLevelBridge(),
                onCancel: nil,
                onPrimary: nil,
                onFinish: nil
            )
            Text("Preview mirrors the live voice invoke pill states.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear {
            thinkingProgress.beginThinkingSession(reduceMotion: reduceMotion)
            phaseIndex = 0
            state = sequence[phaseIndex]
        }
        .onReceive(phaseTimer) { _ in
            guard !sequence.isEmpty else { return }
            phaseIndex = (phaseIndex + 1) % sequence.count
            state = sequence[phaseIndex]
        }
    }
}
