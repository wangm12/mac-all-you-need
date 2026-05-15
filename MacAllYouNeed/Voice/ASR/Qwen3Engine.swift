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

    /// Maximum audio seconds per chunk. Qwen3-ASR's KV cache is 512 tokens;
    /// ~30s of audio already uses ~420 tokens for the audio prompt, leaving
    /// little room for output. Using 25s gives a safe margin.
    private let maxChunkSeconds: Double = 25.0

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
        let manager = try await qwenManager(for: modelID)

        let text: String
        let chunkSize = Int(maxChunkSeconds * Double(Qwen3AsrConfig.sampleRate))

        if qwenSamples.count <= chunkSize {
            // Short recording: transcribe in one pass.
            text = try await manager.transcribe(
                audioSamples: qwenSamples,
                language: languageHint,
                maxNewTokens: 448
            )
        } else {
            // Long recording: split into ≤25s chunks, transcribe each, concatenate.
            // 448 maxNewTokens = 512 cache - ~64 prompt template tokens, maximising
            // output per chunk while staying within the KV cache budget.
            var parts: [String] = []
            var offset = 0
            while offset < qwenSamples.count {
                let end = min(offset + chunkSize, qwenSamples.count)
                let chunk = Array(qwenSamples[offset..<end])
                let part = try await manager.transcribe(
                    audioSamples: chunk,
                    language: languageHint,
                    maxNewTokens: 448
                )
                if !part.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    parts.append(part)
                }
                offset = end
            }
            text = parts.joined(separator: " ")
        }

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
