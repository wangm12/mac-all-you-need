import AppKit
import Core
import SwiftUI

struct VoiceTryItStepView: View {
    let controller: AppController
    let markSucceeded: () -> Void
    @State private var text = ""
    @State private var statusMessage = "Ready. Click the editor, then press the voice shortcut or Start recording."
    @State private var statusKind: StatusPill.Kind = .neutral
    @State private var shouldShowMicPermissionCTA = OnboardingPermissionCTAVisibility.shouldShowMicrophoneCTA()
    private let permissionPoll = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Try it now")
                    .font(.title)
                    .bold()
                Text("Do these 3 steps: click the editor, dictate once, then stop and insert.")
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                VoiceTryItInstructionRow(number: "1", title: "Click the editor", detail: "Keep the text field focused so the app knows where to paste.")
                VoiceTryItInstructionRow(number: "2", title: "Dictate one sentence", detail: "Use the shortcut or the Start recording button.")
                VoiceTryItInstructionRow(number: "3", title: "Stop and insert", detail: "The HUD should turn into a success state and enable Continue.")
            }

            Text("Suggested phrase: 嗨 mingjie, 我们今天 deploy 这个 service 到 production")
                .font(.callout)
                .foregroundStyle(.secondary)

            TextEditor(text: $text)
                .font(.body)
                .frame(minHeight: 150)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                )
            HStack(spacing: 10) {
                MAYNButton("Start recording", role: .primary) {
                    Task { await controller.voiceCoordinator.startRecording() }
                }
                .disabled(controller.voiceCoordinator.state != .idle)
                MAYNButton("Stop and insert") {
                    Task {
                        await controller.voiceCoordinator.stopRecordingAndPaste()
                        if controller.voiceCoordinator.lastTranscript != nil {
                            statusMessage = "Transcript inserted. Continue is now enabled."
                            markSucceeded()
                        } else {
                            statusMessage = "No transcript was produced. Try again or check microphone/model status."
                        }
                    }
                }
                .disabled(controller.voiceCoordinator.state != .recording)
            }
            StatusPill(text: statusMessage, kind: statusKind)
            HStack(spacing: 10) {
                MAYNButton("Open Notes") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Notes.app"))
                }
                if shouldShowMicPermissionCTA {
                    MAYNButton("Mic permissions") {
                        openMicrophoneSettings()
                    }
                }
            }
            if let transcript = controller.voiceCoordinator.lastTranscript {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Raw ASR")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(transcript.rawText)
                        .foregroundStyle(.secondary)
                    Text("Cleaned text")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(transcript.cleanedText)
                        .fontWeight(.semibold)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            Text("Continue unlocks automatically after a successful transcript insert. You can also use Skip for now.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .onChange(of: controller.voiceCoordinator.lastTranscript) { _, transcript in
            guard transcript != nil else { return }
            statusMessage = "Transcript inserted. Continue is now enabled."
            statusKind = .success
            markSucceeded()
        }
        .onAppear {
            shouldShowMicPermissionCTA = OnboardingPermissionCTAVisibility.shouldShowMicrophoneCTA()
        }
        .onReceive(permissionPoll) { _ in
            shouldShowMicPermissionCTA = OnboardingPermissionCTAVisibility.shouldShowMicrophoneCTA()
        }
    }

    private func openMicrophoneSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}

private struct VoiceTryItInstructionRow: View {
    let number: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .frame(width: 24, height: 24)
                .background(Color.primary.opacity(0.08), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
