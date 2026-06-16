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
/// Batch-only: no live streaming session. Model load and inference are dispatched
/// off the cooperative thread pool to avoid actor-thread starvation.
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
        let durationSeconds = Double(resampled.count) / 16000.0
        senseVoiceLog.info("SenseVoice transcribe: \(String(format: "%.1f", durationSeconds), privacy: .public)s audio")

        // Plumb language hint from settings (auto-detect if not set).
        let settings = VoiceASRSettingsStore.load()
        let languageArg: String = switch settings.languageHint {
        case .automatic: "auto"
        case .chinese:   "zh"
        case .english:   "en"
        }

        // generate() is synchronous CPU/MLX work — dispatch off the cooperative pool.
        let output = try await Task.detached(priority: .userInitiated) {
            loadedModel.generate(
                audio: MLXArray(resampled),
                language: languageArg,
                useITN: true,
                verbose: false
            )
        }.value

        // "nospeech" is SenseVoice's signal for no detected speech.
        if output.language == "nospeech" || output.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return VoiceTranscriptionResult(text: "", language: .mixed, modelIdentifier: modelIdentifier)
        }

        let text = output.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return VoiceTranscriptionResult(
            text: text,
            language: Self.voiceLanguage(from: output.language),
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
        // fromDirectory is synchronous and CPU-heavy — dispatch off the cooperative pool.
        let loaded = try await Task.detached(priority: .userInitiated) {
            try SenseVoiceModel.fromDirectory(dir)
        }.value
        model = loaded
        return loaded
    }

    private static func voiceLanguage(from detected: String?) -> VoiceLanguage {
        switch detected {
        case "zh": return .chinese
        case "en": return .english
        default:   return .mixed
        }
    }
}
