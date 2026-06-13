import Core
import FluidAudio
import Foundation
import OSLog

private let localASRLog = Logger(subsystem: "com.macallyouneed.voice", category: "local-asr")

enum VoiceLocalASREngineError: LocalizedError {
    case unsupportedModel(VoiceASRModelID)
    case unsupportedPlatform(String)
    case modelNotInstalled(VoiceASRModelID)

    var errorDescription: String? {
        switch self {
        case let .unsupportedModel(modelID):
            "\(modelID.title) is not supported by the current local ASR runtime."
        case let .unsupportedPlatform(message):
            message
        case let .modelNotInstalled(modelID):
            "\(modelID.title) is not installed. Download it from Voice Models before using Local ASR."
        }
    }
}

actor VoiceLocalASREngine: VoiceLiveTranscriptionEngine, ASRProviding {
    private let qwen = Qwen3Engine()
    private let parakeet = ParakeetEngine()

    nonisolated var modelIdentifier: String {
        VoiceASRSettingsStore.load().modelID.rawValue
    }

    func transcribe(
        samples: [Float],
        sampleRate: Double,
        options: VoiceTranscriptionOptions
    ) async throws -> VoiceTranscriptionResult {
        let settings = VoiceASRSettingsStore.load()
        let modelID = settings.resolvedModelID(preferredModelIdentifier: options.preferredModelIdentifier)

        switch modelID.runtime {
        case .qwenCoreML:
            return try await qwen.transcribe(samples: samples, sampleRate: sampleRate, options: options)
        case .parakeetCoreML:
            return try await parakeet.transcribe(samples: samples, sampleRate: sampleRate, options: options)
        default:
            throw VoiceLocalASREngineError.unsupportedModel(modelID)
        }
    }

    func warmup() async {
        let modelID = VoiceASRSettingsStore.load().modelID
        switch modelID.runtime {
        case .qwenCoreML:
            await qwen.warmup()
        case .parakeetCoreML:
            do {
                if try await parakeet.loadIfInstalled(modelID: modelID) != nil {
                    localASRLog.info("Parakeet ASR warmup complete — model ready")
                }
            } catch {
                localASRLog.error("Parakeet ASR warmup failed: \(error.localizedDescription, privacy: .public)")
            }
        default:
            localASRLog.info("Local ASR warmup skipped — unsupported model: \(modelID.rawValue, privacy: .public)")
        }
    }

    func makeLiveSession(options: VoiceTranscriptionOptions) async throws -> any VoiceLiveTranscriptionSession {
        let settings = VoiceASRSettingsStore.load()
        let modelID = settings.resolvedModelID(preferredModelIdentifier: options.preferredModelIdentifier)
        switch modelID.runtime {
        case .qwenCoreML:
            guard #available(macOS 15, *) else {
                throw Qwen3EngineError.unsupportedOS
            }
            return try await qwen.makeLiveSession(options: options)
        case .parakeetCoreML:
            throw VoiceLiveTranscriptionError.unsupportedEngine
        default:
            throw VoiceLiveTranscriptionError.unsupportedEngine
        }
    }
}

actor ParakeetEngine: VoiceTranscriptionEngine, ASRProviding {
    nonisolated var modelIdentifier: String {
        VoiceASRSettingsStore.load().modelID.rawValue
    }

    private var managers: [VoiceASRModelID: AsrManager] = [:]

    func transcribe(
        samples: [Float],
        sampleRate: Double,
        options: VoiceTranscriptionOptions
    ) async throws -> VoiceTranscriptionResult {
        let settings = VoiceASRSettingsStore.load()
        let modelID = settings.resolvedModelID(preferredModelIdentifier: options.preferredModelIdentifier)
        let manager = try await parakeetManager(for: modelID)
        let parakeetSamples = AudioCaptureService.resample(samples, from: sampleRate, to: 16000)
        let language = settings.languageHint.parakeetLanguage
        let decoderLayers = await manager.decoderLayerCount
        var decoderState = TdtDecoderState.make(decoderLayers: decoderLayers)
        let result = try await manager.transcribe(
            parakeetSamples,
            decoderState: &decoderState,
            language: language
        )

        return VoiceTranscriptionResult(
            text: result.text.trimmingCharacters(in: .whitespacesAndNewlines),
            language: settings.languageHint == .english ? .english : .mixed,
            modelIdentifier: modelID.rawValue
        )
    }

    private func parakeetManager(for modelID: VoiceASRModelID) async throws -> AsrManager {
        if let existing = managers[modelID] { return existing }
        guard let manager = try await loadIfInstalled(modelID: modelID) else {
            throw VoiceLocalASREngineError.modelNotInstalled(modelID)
        }
        return manager
    }

    func loadIfInstalled(modelID: VoiceASRModelID? = nil) async throws -> AsrManager? {
        let modelID = modelID ?? VoiceASRSettingsStore.load().modelID
        guard SystemInfo.isAppleSilicon else {
            throw VoiceLocalASREngineError.unsupportedPlatform("Parakeet requires Apple Silicon.")
        }
        guard let version = modelID.parakeetVersion else {
            throw VoiceLocalASREngineError.unsupportedModel(modelID)
        }
        if let existing = managers[modelID] { return existing }

        let cacheDir = VoiceModelManager.localASRCacheDirectory(for: modelID)
        guard AsrModels.modelsExist(at: cacheDir, version: version) else {
            localASRLog.info("Parakeet warmup skipped — model not installed: \(modelID.rawValue, privacy: .public)")
            return nil
        }

        localASRLog.info("Parakeet model load start — version: \(String(describing: version), privacy: .public)")
        let models = try await AsrModels.load(from: cacheDir, version: version)
        let manager = AsrManager(models: models)
        managers[modelID] = manager
        localASRLog.info("Parakeet model loaded and ready — version: \(String(describing: version), privacy: .public)")
        return manager
    }

    func downloadAndLoad(
        modelID: VoiceASRModelID,
        progressHandler: DownloadUtils.ProgressHandler? = nil
    ) async throws {
        _ = try await VoiceModelManager.downloadLocalASRModel(modelID, progressHandler: progressHandler)
        _ = try await loadIfInstalled(modelID: modelID)
    }
}
