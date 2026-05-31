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
                Text("Hybrid and Auto-VAD are visible here for the v1 setup catalog; runtime support lands in the multi-engine phase.")
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
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "mic.fill")
                .foregroundStyle(.primary)
            Text("Listening")
                .font(.headline)
            ProgressView(value: 0.55)
                .frame(width: 140)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
