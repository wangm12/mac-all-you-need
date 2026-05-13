import Core
import FluidAudio
import Foundation

enum Qwen3EngineError: LocalizedError {
    case unsupportedOS

    var errorDescription: String? {
        switch self {
        case .unsupportedOS:
            "Qwen3-ASR requires macOS 15 or later."
        }
    }
}

actor Qwen3Engine: VoiceTranscriptionEngine {
    nonisolated let modelIdentifier = "qwen3-asr-0.6b-f32"
    private var manager: Any?

    func transcribe(samples: [Float], sampleRate: Double) async throws -> VoiceTranscriptionResult {
        guard #available(macOS 15, *) else { throw Qwen3EngineError.unsupportedOS }
        let qwenSamples = AudioCaptureService.resample(samples, from: sampleRate, to: 16000)
        let languageHint = VoiceASRSettingsStore.load().languageHint.qwen3Language
        let text = try await qwenManager().transcribe(
            audioSamples: qwenSamples,
            language: languageHint,
            maxNewTokens: 512
        )
        return VoiceTranscriptionResult(text: text, language: .mixed, modelIdentifier: modelIdentifier)
    }

    @available(macOS 15, *)
    private func qwenManager() async throws -> Qwen3AsrManager {
        if let existing = manager as? Qwen3AsrManager { return existing }
        let cacheDir = try await Qwen3AsrModels.download(variant: .f32)
        let next = Qwen3AsrManager()
        try await next.loadModels(from: cacheDir)
        manager = next
        return next
    }
}
