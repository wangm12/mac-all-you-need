import Core
import FluidAudio
import Foundation
import OSLog

private let log = Logger(subsystem: "com.macallyouneed.voice", category: "asr")

enum Qwen3EngineError: LocalizedError {
    case unsupportedOS
    case modelNotInstalled(VoiceASRModelID)

    var errorDescription: String? {
        switch self {
        case .unsupportedOS:
            "Qwen3-ASR requires macOS 15 or later."
        case let .modelNotInstalled(modelID):
            "\(modelID.title) is not installed. Download it from Voice Models before using Local ASR."
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
        guard modelID.qwen3Variant != nil else {
            throw VoiceLocalASREngineError.unsupportedModel(modelID)
        }
        if let existing = managers[modelID] as? Qwen3AsrManager { return existing }
        guard let manager = try await loadIfInstalled(modelID: modelID) else {
            throw Qwen3EngineError.modelNotInstalled(modelID)
        }
        return manager
    }

    @available(macOS 15, *)
    func loadIfInstalled(modelID: VoiceASRModelID? = nil) async throws -> Qwen3AsrManager? {
        let modelID = modelID ?? VoiceASRSettingsStore.load().modelID
        guard let variant = modelID.qwen3Variant else {
            throw VoiceLocalASREngineError.unsupportedModel(modelID)
        }
        if let existing = managers[modelID] as? Qwen3AsrManager { return existing }
        let cacheDir = VoiceModelManager.localASRCacheDirectory(for: modelID)
        guard Qwen3AsrModels.modelsExist(at: cacheDir) else {
            log.info("ASR warmup skipped — model not installed: \(modelID.rawValue, privacy: .public)")
            return nil
        }
        log.info("ASR model load start — variant: \(String(describing: variant), privacy: .public)")
        let next = Qwen3AsrManager()
        try await next.loadModels(from: cacheDir)
        log.info("ASR model loaded and ready — variant: \(String(describing: variant), privacy: .public)")
        managers[modelID] = next
        return next
    }

    @available(macOS 15, *)
    func downloadAndLoad(
        modelID: VoiceASRModelID,
        progressHandler: DownloadUtils.ProgressHandler? = nil
    ) async throws {
        guard let variant = modelID.qwen3Variant else {
            throw VoiceLocalASREngineError.unsupportedModel(modelID)
        }
        let cacheDir = try await Qwen3AsrModels.download(
            variant: variant,
            progressHandler: progressHandler
        )
        let next = Qwen3AsrManager()
        try await next.loadModels(from: cacheDir)
        managers[modelID] = next
    }

    /// Loads the configured model in the background only when it is already installed.
    /// Downloads are explicit user actions from setup/model-management surfaces.
    func warmup() async {
        guard #available(macOS 15, *) else { return }
        let settings = VoiceASRSettingsStore.load()
        let modelID = settings.modelID
        guard managers[modelID] == nil else { return }  // already loaded
        log.info("ASR warmup starting for model: \(modelID.rawValue, privacy: .public)")
        do {
            if try await loadIfInstalled(modelID: modelID) != nil {
                log.info("ASR warmup complete — model ready")
            }
        } catch {
            log.error("ASR warmup failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
