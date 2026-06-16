import Core
import Foundation
import MLX
import MLXAudioCore
import MLXAudioSTT
import OSLog

private let senseVoiceLog = Logger(
    subsystem: "com.macallyouneed.voice",
    category: "sensevoice"
)

/// Non-autoregressive CTC ASR engine using SenseVoice Small via mlx-audio-swift.
/// Batch-only: no live streaming session.
actor SenseVoiceEngine: VoiceTranscriptionEngine {

    private var model: SenseVoiceModel?

    nonisolated var modelIdentifier: String { "sense-voice-small" }

    nonisolated var capabilities: VoiceASRCapabilities { .batchOnly }

    func transcribe(
        samples: [Float],
        sampleRate: Double,
        options: VoiceTranscriptionOptions
    ) async throws -> VoiceTranscriptionResult {
        let loadedModel = try await loadModelIfNeeded()
        let resampled = sampleRate == 16000
            ? samples
            : AudioCaptureService.resample(samples, from: sampleRate, to: 16000)
        senseVoiceLog.info("SenseVoice transcribe: \(resampled.count / 16000, privacy: .public)s audio")
        let output = loadedModel.generate(
            audio: MLXArray(resampled),
            language: "auto",
            useITN: true,
            verbose: false
        )
        let text = output.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let language = voiceLanguage(from: output.language)
        return VoiceTranscriptionResult(
            text: text,
            language: language,
            modelIdentifier: modelIdentifier
        )
    }

    func warmup() async {
        _ = try? await loadModelIfNeeded()
    }

    // MARK: - Private

    private func loadModelIfNeeded() async throws -> SenseVoiceModel {
        if let existing = model { return existing }
        let dir = SenseVoiceModels.defaultCacheDirectory()
        guard SenseVoiceModels.modelsExist(at: dir) else {
            throw VoiceLocalASREngineError.modelNotInstalled(.senseVoiceSmall)
        }
        senseVoiceLog.info("SenseVoice: loading model from \(dir.path, privacy: .public)")
        let loaded = try SenseVoiceModel.fromDirectory(dir)
        model = loaded
        return loaded
    }

    private nonisolated func voiceLanguage(from detected: String?) -> VoiceLanguage {
        switch detected {
        case "zh": return .chinese
        case "en": return .english
        default: return .mixed
        }
    }
}
