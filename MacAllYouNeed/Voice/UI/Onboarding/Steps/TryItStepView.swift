import AppKit
import Core
import SwiftUI

struct VoiceTryItStepView: View {
    let controller: AppController
    let markSucceeded: () -> Void
    @State private var text = ""
    @State private var statusMessage = "Click inside the editor, then use the shortcut or buttons to dictate."
    @State private var shouldShowMicPermissionCTA = OnboardingPermissionCTAVisibility.shouldShowMicrophoneCTA()
    private let permissionPoll = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Try it now")
                .font(.title)
                .bold()
            Text("Suggested phrase: 嗨 mingjie, 我们今天 deploy 这个 service 到 production")
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
            Text(statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Continue unlocks automatically after a successful transcript insert. You can also use Skip for now.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .onChange(of: controller.voiceCoordinator.lastTranscript) { _, transcript in
            guard transcript != nil else { return }
            statusMessage = "Transcript inserted. Continue is now enabled."
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
