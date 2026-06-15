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

    nonisolated var capabilities: VoiceASRCapabilities {
        .init(supportsStreaming: true, requiresNetwork: false, emitsPartials: false)
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
        let manager = try await qwenManager(for: modelID)

        let text: String
        let chunkSize = VoiceLongFormASRPlanning.maxSegmentSamples
        let maxNewTokens = VoiceLongFormASRPlanning.maxNewTokensPerPass

        if qwenSamples.count <= chunkSize {
            text = try await manager.transcribe(
                audioSamples: qwenSamples,
                language: languageHint,
                maxNewTokens: maxNewTokens
            )
        } else {
            var parts: [String] = []
            var offset = 0
            let stride = VoiceLongFormASRPlanning.batchStrideSamples
            while offset < qwenSamples.count {
                let end = min(offset + chunkSize, qwenSamples.count)
                let chunk = Array(qwenSamples[offset..<end])
                let part = try await manager.transcribe(
                    audioSamples: chunk,
                    language: languageHint,
                    maxNewTokens: maxNewTokens
                )
                if !part.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    parts.append(part)
                }
                if end >= qwenSamples.count { break }
                offset += stride
            }
            text = VoiceSequentialTranscriptMerge.mergeSequential(parts)
        }

        return VoiceTranscriptionResult(text: text, language: .mixed, modelIdentifier: modelID.rawValue)
    }

    @available(macOS 15, *)
    func makeLiveSession(options: VoiceTranscriptionOptions) async throws -> any VoiceLiveTranscriptionSession {
        let settings = VoiceASRSettingsStore.load()
        let modelID = settings.resolvedModelID(preferredModelIdentifier: options.preferredModelIdentifier)
        let manager = try await qwenManager(for: modelID)
        return Qwen3LongFormLiveSession(
            manager: manager,
            modelID: modelID,
            languageHint: settings.languageHint.qwen3Language
        )
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

@available(macOS 15, *)
private actor Qwen3LongFormLiveSession: VoiceLiveTranscriptionSession {
    private let manager: Qwen3AsrManager
    private let modelID: VoiceASRModelID
    private let languageHint: Qwen3AsrConfig.Language?
    private var pendingSamples: [Float] = []
    private var committedParts: [String] = []
    private var cancelled = false

    init(
        manager: Qwen3AsrManager,
        modelID: VoiceASRModelID,
        languageHint: Qwen3AsrConfig.Language?
    ) {
        self.manager = manager
        self.modelID = modelID
        self.languageHint = languageHint
    }

    func enqueueAudio(samples: [Float], sampleRate: Double) async throws {
        guard !cancelled else { return }
        let resampled = AudioCaptureService.resample(samples, from: sampleRate, to: 16000)
        guard !resampled.isEmpty else { return }
        pendingSamples.append(contentsOf: resampled)
        try await commitSegmentsIfNeeded()
    }

    func finish() async throws -> VoiceTranscriptionResult {
        try await finish(context: nil)
    }

    func finish(context: VoiceLiveFinishContext?) async throws -> VoiceTranscriptionResult {
        guard !cancelled else { throw VoiceLiveTranscriptionError.cancelled }
        try await commitSegmentsIfNeeded()

        let tailText = try await resolveTailText(context: context)
        if !tailText.isEmpty {
            committedParts.append(tailText)
        }
        pendingSamples.removeAll(keepingCapacity: false)

        let text = VoiceSequentialTranscriptMerge.mergeSequential(committedParts)
        return VoiceTranscriptionResult(
            text: text,
            language: .mixed,
            modelIdentifier: modelID.rawValue
        )
    }

    private func resolveTailText(context: VoiceLiveFinishContext?) async throws -> String {
        guard !pendingSamples.isEmpty || context != nil else { return "" }

        let pendingTailText: String
        if pendingSamples.isEmpty {
            pendingTailText = ""
        } else {
            pendingTailText = try await transcribe(samples: pendingSamples)
        }

        guard let context, !context.samples.isEmpty else {
            return pendingTailText
        }

        let plan = VoiceLongFormASRPlanning.tailTranscriptionPlan(
            totalCapturedCount: context.samples.count,
            capturedSampleRate: context.sampleRate,
            committedPartCount: committedParts.count,
            pendingCount: pendingSamples.count
        )

        guard plan.useWidenedTail, plan.tailSampleCount > 0 else {
            return pendingTailText
        }

        let widenedSource = Array(context.samples.suffix(plan.tailSampleCount))
        let widenedResampled = AudioCaptureService.resample(
            widenedSource,
            from: context.sampleRate,
            to: Double(VoiceLongFormASRPlanning.sampleRate)
        )
        guard !widenedResampled.isEmpty else { return pendingTailText }

        let widenedTailText = try await transcribe(samples: widenedResampled)
        let committedText = VoiceSequentialTranscriptMerge.mergeSequential(committedParts)
        if VoiceLongFormTailMergePolicy.shouldUseWidenedTailMerge(
            pendingTailText: pendingTailText,
            widenedTailText: widenedTailText,
            committedTextBeforeTail: committedText
        ) {
            return widenedTailText
        }
        return pendingTailText
    }

    func cancel() async {
        cancelled = true
        pendingSamples.removeAll(keepingCapacity: false)
        committedParts.removeAll(keepingCapacity: false)
    }

    private func commitSegmentsIfNeeded() async throws {
        while let commitCount = VoiceLongFormASRPlanning.samplesToCommit(pendingCount: pendingSamples.count) {
            let chunk = Array(pendingSamples.prefix(commitCount))
            let part = try await transcribe(samples: chunk)
            if !part.isEmpty {
                committedParts.append(part)
            }
            pendingSamples.removeFirst(commitCount)
        }
    }

    private func transcribe(samples: [Float]) async throws -> String {
        let part = try await manager.transcribe(
            audioSamples: samples,
            language: languageHint,
            maxNewTokens: VoiceLongFormASRPlanning.maxNewTokensPerPass
        )
        return part.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
