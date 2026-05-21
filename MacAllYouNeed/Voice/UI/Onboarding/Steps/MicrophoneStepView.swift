import AVFAudio
import AVFoundation
import SwiftUI

struct VoiceMicrophoneStepView: View {
    let autoAdvance: () -> Void
    @State private var permission = AVCaptureDevice.authorizationStatus(for: .audio)
    @State private var audio = AudioCaptureService()
    @State private var isCapturing = false
    @State private var visualLevel = 0.0
    @State private var audioDetectedAt: Date?
    @State private var didAutoAdvance = false
    @State private var showsInstruction = false
    @State private var statusMessage = "macOS will ask for permission when you continue."
    private let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    var body: some View {
        SetupTaskPage(
            symbol: "mic",
            title: "Allow microphone access",
            subtitle: "Voice dictation needs microphone access to capture audio locally before transcription."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                PermissionCard(
                    title: "Microphone",
                    reason: "macOS will ask once. After access is granted, speak briefly to confirm input level.",
                    state: permissionCardState,
                    actionTitle: permission == .authorized ? "Microphone granted" : "Request access",
                    action: requestPermission
                )
                if showsInstruction && permission != .authorized {
                    InstructionStrip(
                        text: "Choose Allow in the macOS microphone prompt.",
                        symbol: "mic.badge.plus"
                    )
                }
                if permission == .authorized {
                    VStack(alignment: .leading, spacing: 8) {
                        ProgressView(value: visualLevel, total: 1)
                        Text("This step advances automatically after audio is detected.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .background(MAYNTheme.panel, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(MAYNTheme.subtleBorder, lineWidth: 1)
                    )
                }
                MAYNButton("Open Microphone Settings") {
                    showsInstruction = true
                    openSystemSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
                }
                permissionLabel
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            if permission == .authorized {
                startCapture()
            }
        }
        .onDisappear {
            stopCapture()
        }
        .onReceive(timer) { _ in
            updateAudioDetection()
        }
    }

    private var permissionCardState: PermissionCard.StateKind {
        switch permission {
        case .authorized:
            .granted
        case .denied, .restricted:
            .denied
        case .notDetermined:
            .needed
        @unknown default:
            .needed
        }
    }

    @ViewBuilder
    private var permissionLabel: some View {
        switch permission {
        case .authorized:
            Label("Granted", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.primary)
        case .denied, .restricted:
            Label("Permission is blocked. Enable it in System Settings.", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.secondary)
        case .notDetermined:
            Text("Waiting for permission.")
                .foregroundStyle(.secondary)
        @unknown default:
            Text("Unknown microphone permission state.")
                .foregroundStyle(.secondary)
        }
    }

    private func requestPermission() {
        showsInstruction = permission != .authorized
        Task {
            let granted = await Self.requestRecordPermission()
            permission = granted ? .authorized : .denied
            statusMessage = granted
                ? "Microphone granted. Starting live level check..."
                : "Microphone access was denied."
            if granted {
                showsInstruction = false
                startCapture()
            }
        }
    }

    private func startCapture() {
        guard !isCapturing else { return }
        do {
            try audio.start()
            isCapturing = true
            statusMessage = "Listening for input level..."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func stopCapture() {
        _ = audio.stop()
        isCapturing = false
        audioDetectedAt = nil
    }

    private func updateAudioDetection() {
        guard permission == .authorized, isCapturing, !didAutoAdvance else { return }
        let peak = Double(audio.peakLevel)
        visualLevel = min(max(peak * 4, 0), 1)
        guard peak > 0.02 else { return }

        let now = Date()
        if audioDetectedAt == nil {
            audioDetectedAt = now
            statusMessage = "Audio detected. Keep speaking briefly..."
        }
        guard let audioDetectedAt,
              now.timeIntervalSince(audioDetectedAt) >= 1.5
        else {
            return
        }
        didAutoAdvance = true
        stopCapture()
        autoAdvance()
    }

    private static func requestRecordPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}
