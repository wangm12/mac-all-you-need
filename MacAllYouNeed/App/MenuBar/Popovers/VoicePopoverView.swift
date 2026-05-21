import ApplicationServices
import AVFoundation
import Core
import SwiftUI

struct VoicePopoverView: View {
    let controller: AppController

    @State private var micPermission = AVCaptureDevice.authorizationStatus(for: .audio)

    private var coordinator: VoiceCoordinator {
        controller.voiceCoordinator
    }

    private var activationSettings: VoiceActivationSettings {
        VoiceActivationSettingsStore.load()
    }

    private var asrSettings: VoiceASRSettings {
        VoiceASRSettingsStore.load()
    }

    private var onboardingProgress: VoiceOnboardingProgress {
        VoiceOnboardingProgressStore.load()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Voice")
                            .font(.system(size: 22, weight: .semibold))
                        Text(stateTitle)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    ShortcutChip(text: activationSettings.shortcut.display)
                }

                HStack(spacing: 8) {
                    VoiceCommandButton(
                        title: coordinator.state == .recording ? "Stop & Paste" : "Start",
                        symbol: coordinator.state == .recording ? "checkmark" : "mic"
                    ) {
                        if coordinator.state == .recording {
                            Task { await coordinator.stopRecordingAndPaste() }
                        } else {
                            Task { await coordinator.startRecording() }
                        }
                    }
                    .disabled(!canToggleRecording)

                    VoiceCommandButton(title: "Setup", symbol: "slider.horizontal.3") {
                        NSApp.activate(ignoringOtherApps: true)
                        controller.showVoiceOnboarding()
                    }

                    VoiceCommandButton(title: "Dictionary", symbol: "text.book.closed") {
                        AppGroupSettings.defaults.set(VoiceFunctionTab.dictionary.rawValue, forKey: VoiceFunctionTab.storageKey)
                        controller.showMainWindow(destination: .voice)
                    }

                    VoiceCommandButton(title: "Mic", symbol: "mic.badge.plus") {
                        Task { await refreshMicrophonePermission(requestIfNeeded: true) }
                    }
                    .disabled(micPermission == .authorized)
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    VoiceStatusTile(title: "Mode", value: activationSettings.mode.label, symbol: "switch.2")
                    VoiceStatusTile(title: "Language", value: asrSettings.languageHint.label, symbol: "textformat")
                    VoiceStatusTile(title: "Microphone", value: microphoneStatusText, symbol: "mic")
                    VoiceStatusTile(title: "Accessibility", value: accessibilityStatusText, symbol: "keyboard")
                    VoiceStatusTile(title: "Setup", value: onboardingProgress.isCompleted ? "Complete" : onboardingProgress.currentStep.title, symbol: "checklist")
                    VoiceStatusTile(title: "Cleanup", value: cleanupStatusText, symbol: "sparkles")
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Last transcript")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        if let transcript = coordinator.lastTranscript {
                            Text(transcript.usedLLM ? "LLM" : "Local")
                                .font(.system(size: 10, weight: .semibold))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color.primary.opacity(0.08), in: Capsule())
                        }
                    }

                    Text(lastTranscriptText)
                        .font(.system(size: 13))
                        .foregroundStyle(coordinator.lastTranscript == nil ? .tertiary : .primary)
                        .lineLimit(6)
                        .frame(maxWidth: .infinity, minHeight: 86, alignment: .topLeading)
                        .padding(12)
                        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.10), lineWidth: 1))
                }
            }
            .padding(16)
        }
        .task {
            await refreshMicrophonePermission(requestIfNeeded: false)
        }
    }

    private var canToggleRecording: Bool {
        switch coordinator.state {
        case .idle, .recording:
            true
        case .transcribing, .pasting, .error:
            false
        }
    }

    private var stateTitle: String {
        switch coordinator.state {
        case .idle:
            "Ready for dictation"
        case .recording:
            "Listening"
        case .transcribing:
            "Transcribing audio"
        case .pasting:
            "Pasting into the focused app"
        case let .error(message):
            message
        }
    }

    private var lastTranscriptText: String {
        guard let transcript = coordinator.lastTranscript else {
            return "No transcript captured yet."
        }
        return transcript.cleanedText.isEmpty ? transcript.rawText : transcript.cleanedText
    }

    private var microphoneStatusText: String {
        switch micPermission {
        case .authorized:
            "Granted"
        case .notDetermined:
            "Not requested"
        case .denied:
            "Denied"
        case .restricted:
            "Restricted"
        @unknown default:
            "Unknown"
        }
    }

    private var accessibilityStatusText: String {
        AXIsProcessTrusted() ? "Granted" : "Needs access"
    }

    private var cleanupStatusText: String {
        let settings = controller.voiceCleanupSettings()
        return settings.isEnabled ? settings.provider.label : "Local"
    }

    private func refreshMicrophonePermission(requestIfNeeded: Bool) async {
        if requestIfNeeded, micPermission == .notDetermined {
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            micPermission = granted ? .authorized : AVCaptureDevice.authorizationStatus(for: .audio)
        } else {
            micPermission = AVCaptureDevice.authorizationStatus(for: .audio)
        }
    }
}

// MARK: - Supporting views

private struct VoiceStatusTile: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 24, height: 24)
                .background(Color.primary.opacity(0.08), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                Text(value)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(minHeight: 58, alignment: .topLeading)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.10), lineWidth: 1))
    }
}

private struct VoiceCommandButton: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        MAYNButton(role: .primary, height: MAYNControlMetrics.controlHeight, action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
        }
    }
}
