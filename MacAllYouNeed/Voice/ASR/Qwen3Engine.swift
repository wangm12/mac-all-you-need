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
    nonisolated var modelIdentifier: String {
        VoiceASRSettingsStore.load().modelID.rawValue
    }
    private var managers: [VoiceASRModelID: Any] = [:]

    func transcribe(
        samples: [Float],
        sampleRate: Double,
        options: VoiceTranscriptionOptions
    ) async throws -> VoiceTranscriptionResult {
        guard #available(macOS 15, *) else { throw Qwen3EngineError.unsupportedOS }
        let settings = VoiceASRSettingsStore.load()
        let modelID = settings.resolvedModelID(preferredModelIdentifier: options.preferredModelIdentifier)
        let qwenSamples = AudioCaptureService.resample(samples, from: sampleRate, to: 16000)
        let languageHint = settings.languageHint.qwen3Language
        let text = try await qwenManager(for: modelID).transcribe(
            audioSamples: qwenSamples,
            language: languageHint,
            maxNewTokens: 8192
        )
        return VoiceTranscriptionResult(text: text, language: .mixed, modelIdentifier: modelID.rawValue)
    }

    @available(macOS 15, *)
    private func qwenManager(for modelID: VoiceASRModelID) async throws -> Qwen3AsrManager {
        if let existing = managers[modelID] as? Qwen3AsrManager { return existing }
        let cacheDir = try await Qwen3AsrModels.download(variant: modelID.variant)
        let next = Qwen3AsrManager()
        try await next.loadModels(from: cacheDir)
        managers[modelID] = next
        return next
    }
}
