import AppKit
import Core
import Foundation
import OSLog
import Platform

/// Delegate protocol through which VoicePipelineController reads and writes
/// coordinator state without holding a strong typed reference to
/// VoiceCoordinator itself.
@MainActor
protocol VoicePipelineDelegate: AnyObject {
    var state: VoiceCoordinator.State { get set }
    var operationGeneration: Int { get set }
    var activeIntent: VoiceIntent { get set }
    var activeEngine: (any ASRProviding)? { get }
    var isStoppingRecording: Bool { get set }
    var pendingPipelineMetrics: VoicePipelineController.PipelineMetrics? { get set }
    var inputSourceChangedDuringRun: Bool { get set }
    var inputSourceAtRecordingStart: String? { get set }
    var lastTranscript: VoiceCleanupResult? { get set }
    var lastCreatedReminder: CreatedReminder? { get set }

    /// Called by the pipeline to ask whether a spoken prefix warrants promoting
    /// the active intent to .reminder. Defined in VoiceCoordinator+Reminders.
    func maybePromoteToReminderIntent(rawText: String?)
    /// Reminder terminal: write to Reminders and tear down. Defined in
    /// VoiceCoordinator+Reminders.
    func finishReminderRun(cleanedText: String, writer: any RemindersWriter, generation: Int) async throws
    /// Returns the reminder writer for the current run (production or override).
    func resolveReminderWriter() -> (any RemindersWriter)?
    /// Mirror of reminderSettings — pipeline passes it to ReminderWritePhase.
    var reminderSettings: () -> ReminderSettings { get }
}

// MARK: -

/// Owns the ASR pipeline, live-ASR session management, processCapturedAudio,
/// undo replay, transcript persistence, and the retry-from-history flow.
/// VoiceCoordinator holds one as a stored property and delegates all of the
/// above through it.
@MainActor
final class VoicePipelineController {

    // MARK: - Nested types visible to tests / callers

    struct PipelineMetrics {
        let recordingMs: Int
        let liveFinishMs: Int
        let liveUsed: Bool
    }

    private struct VoiceStageTimeouts {
        static let liveFinalizeSeconds: TimeInterval = 0.8
        static let cleanupSeconds: TimeInterval = 12.0
        static let pasteSeconds: TimeInterval = 2.0
    }

    // MARK: - Dependencies

    private let transcripts: VoiceTranscriptStore
    private let dictionary: VoiceDictionaryStore?
    private let personalizationStore: VoicePersonalizationStore?
    private let trainingExampleStore: VoiceTrainingExampleStore?
    private let personalizationSettings: () -> VoicePersonalizationSettings
    private let historySettings: () -> VoiceHistorySettings
    private let cleanupKeyStore: VoiceCleanupKeyStore
    private let learningMonitor: VoicePostEditLearningMonitor
    private let summarizer: VoicePersonalizationSummarizer?
    let log: Logger

    // MARK: - Test seams (nil → production path)

    let cleanupPipelineFactoryOverride: ((TimeInterval) -> VoiceCleanupPipeline)?
    let pasterOverride: ((String, AXTargetSnapshot?) async -> CursorPaster.Result)?
    let snapshotFocusedOverride: (() -> AXTargetSnapshot?)?
    let learningStarterOverride: ((String, String?, String?, Bool, AXTargetSnapshot?) -> Void)?
    let cleanupObserver: ((VoiceCleanupRequest) -> Void)?

    // MARK: - Collaborators (set by VoiceCoordinator after init)

    weak var delegate: (any VoicePipelineDelegate)?
    var hudPresenter: VoiceHUDPresenter?
    let undoBookkeeping = UndoContextBookkeeping()

    // MARK: - Live ASR state

    private let liveFeed = VoiceLiveAudioFeed()
    private var liveSession: (any VoiceLiveTranscriptionSession)?
    private var liveSessionGeneration = 0
    private var liveFeedTask: Task<Void, Never>?

    // MARK: - Learning monitor task

    private var monitorTask: Task<Void, Never>?

    // MARK: - Undo expiration

    private var undoExpirationTask: Task<Void, Never>?
    private static let undoWindowSeconds: TimeInterval = 5

    // MARK: - Init

    // swiftlint:disable:next function_parameter_count
    init(
        transcripts: VoiceTranscriptStore,
        dictionary: VoiceDictionaryStore?,
        personalizationStore: VoicePersonalizationStore?,
        trainingExampleStore: VoiceTrainingExampleStore?,
        personalizationSettings: @escaping () -> VoicePersonalizationSettings,
        cleanupKeyStore: VoiceCleanupKeyStore,
        learningMonitor: VoicePostEditLearningMonitor?,
        summarizer: VoicePersonalizationSummarizer?,
        historySettings: @escaping () -> VoiceHistorySettings,
        cleanupPipelineFactory: ((TimeInterval) -> VoiceCleanupPipeline)?,
        paster: ((String, AXTargetSnapshot?) async -> CursorPaster.Result)?,
        snapshotFocused: (() -> AXTargetSnapshot?)?,
        learningStarter: ((String, String?, String?, Bool, AXTargetSnapshot?) -> Void)?,
        cleanupObserver: ((VoiceCleanupRequest) -> Void)?,
        log: Logger
    ) {
        self.transcripts = transcripts
        self.dictionary = dictionary
        self.personalizationStore = personalizationStore
        self.trainingExampleStore = trainingExampleStore
        self.personalizationSettings = personalizationSettings
        self.cleanupKeyStore = cleanupKeyStore
        self.learningMonitor = learningMonitor ?? VoicePostEditLearningMonitor()
        self.summarizer = summarizer
        self.historySettings = historySettings
        cleanupPipelineFactoryOverride = cleanupPipelineFactory
        pasterOverride = paster
        snapshotFocusedOverride = snapshotFocused
        learningStarterOverride = learningStarter
        self.cleanupObserver = cleanupObserver
        self.log = log
    }

    // MARK: - Live ASR session

    func beginLiveASR(generation: Int, audioSnapshotProvider: @escaping () -> (samples: [Float], sampleRate: Double)?) async {
        guard let liveEngine = delegate?.activeEngine as? VoiceLiveTranscriptionEngine else { return }
        do {
            let session = try await liveEngine.makeLiveSession(options: .default)
            liveSession = session
            liveSessionGeneration = generation
            await liveFeed.reset()
            liveFeedTask = Task { [weak self] in
                guard let self else { return }
                while !Task.isCancelled {
                    guard let d = self.delegate,
                          d.operationGeneration == generation,
                          d.state == .recording else { return }
                    guard let snapshot = audioSnapshotProvider() else {
                        try? await Task.sleep(nanoseconds: 50_000_000)
                        continue
                    }
                    do {
                        try await self.liveFeed.drain(snapshot: snapshot, into: session)
                    } catch {
                        self.log.warning("live ASR feed stopped: \(error.localizedDescription, privacy: .public)")
                        return
                    }
                    try? await Task.sleep(nanoseconds: 50_000_000)
                }
            }
            log.info("live ASR session started — generation: \(generation, privacy: .public)")
        } catch {
            log.warning("live ASR session unavailable: \(error.localizedDescription, privacy: .public)")
            liveSession = nil
        }
    }

    func drainLiveFeed(snapshot: (samples: [Float], sampleRate: Double)) async throws {
        guard let session = liveSession else { return }
        try await liveFeed.drain(snapshot: snapshot, into: session)
    }

    func finishLiveASRIfEligible(
        captured: CapturedAudio,
        generation: Int
    ) async -> VoiceTranscriptionResult? {
        guard generation == liveSessionGeneration,
              let session = liveSession
        else {
            await cancelLiveASR()
            return nil
        }

        do {
            let finishContext = VoiceLiveFinishContext(
                samples: captured.samples,
                sampleRate: captured.sampleRate
            )
            let result = try await session.finish(context: finishContext)
            guard generation == liveSessionGeneration else { return nil }
            liveSession = nil
            let trimmed = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                log.info("live ASR finish empty — using batch fallback")
                await cancelLiveASR()
                return nil
            }
            let reconciled = VoiceTranscriptionResult(
                text: trimmed,
                language: result.language,
                modelIdentifier: result.modelIdentifier
            )
            if delegate?.activeEngine is VoiceLocalASREngine,
               VoiceLiveASRQualityCheck.looksSuspicious(result: reconciled, captured: captured)
            {
                log.info("live ASR reconcile — batch fallback, reason: lowCharsPerSec")
                await cancelLiveASR()
                return nil
            }
            log.info("live ASR finish — chars: \(trimmed.count, privacy: .public)")
            return reconciled
        } catch {
            log.warning("live ASR finish failed — batch fallback: \(error.localizedDescription, privacy: .public)")
            await cancelLiveASR()
            return nil
        }
    }

    func cancelLiveASR() async {
        liveFeedTask?.cancel()
        liveFeedTask = nil
        if let session = liveSession {
            await session.cancel()
        }
        liveSession = nil
        await liveFeed.reset()
    }

    func stopLiveFeedTask() {
        liveFeedTask?.cancel()
        liveFeedTask = nil
    }

    var currentLiveSessionGeneration: Int { liveSessionGeneration }

    func currentLiveSessionSnapshot() -> (any VoiceLiveTranscriptionSession)? { liveSession }

    // MARK: - processCapturedAudio

    /// Drives the ASR → cleanup → paste → save → learning pipeline. Internal
    /// (not private) so the spine test can drive it end-to-end. Shared by the
    /// live `stopRecordingAndPaste` entry and by `undoLastCancel`.
    func processCapturedAudio(
        captured: CapturedAudio,
        presetASRResult: VoiceTranscriptionResult?,
        presetAppBundleID: String?,
        retrySourceTranscriptID: String? = nil
    ) async {
        guard let delegate else { return }
        delegate.operationGeneration += 1
        let generation = delegate.operationGeneration
        let appBundleID = presetAppBundleID ?? NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        delegate.state = .transcribing
        delegate.isStoppingRecording = false
        undoBookkeeping.setInflight(captured: captured, appBundleID: appBundleID, asrResult: presetASRResult)
        hudPresenter?.showTranscribingPhase(presetASRResult == nil ? .asr : .cleanup(progress: 0))
        log.info("ASR start — app: \(appBundleID ?? "nil", privacy: .public) presetASR: \(presetASRResult != nil, privacy: .public)")

        var ctx = VoicePipelineContext(
            captured: captured,
            presetASRResult: presetASRResult,
            appBundleID: appBundleID,
            generation: generation,
            retrySourceTranscriptID: retrySourceTranscriptID,
            operationStartedAt: Date()
        )
        ctx.liveFinalizeMs = delegate.pendingPipelineMetrics?.liveFinishMs

        do {
            // Phase 1 — ASR.
            try await ASRPhase(engine: delegate.activeEngine, log: log).run(&ctx)
            guard checkpoint(generation, delegate: delegate) else { return }
            if presetASRResult == nil, let asr = ctx.asrResult {
                undoBookkeeping.setInflightASRResult(asr)
            }

            delegate.maybePromoteToReminderIntent(rawText: ctx.asrResult?.text)

            // Phase 2 — Cleanup.
            hudPresenter?.showTranscribingPhase(.cleanup(progress: 0))
            let cleanupStartedAt = Date()
            let cleanupCompleted = await withTimeout(seconds: VoiceStageTimeouts.cleanupSeconds) {
                await self.makeCleanupPhase(bundleID: appBundleID, generation: generation).run(&ctx)
                return true
            } ?? false
            let cleanupMs = Int(Date().timeIntervalSince(cleanupStartedAt) * 1000)
            ctx.cleanupMs = cleanupMs
            guard checkpoint(generation, delegate: delegate) else { return }
            if !cleanupCompleted {
                log.error("processCapturedAudio: cleanup timed out, falling back to raw ASR text")
                let fallbackText = (ctx.asrResult?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !fallbackText.isEmpty else {
                    undoBookkeeping.clearInflight()
                    await failPipeline(
                        message: "ASR returned empty transcript",
                        stage: .cleanup,
                        reason: "cleanup_timeout_empty_fallback",
                        ctx: ctx
                    )
                    return
                }
                let fallbackResult = VoiceCleanupResult(
                    rawText: fallbackText,
                    cleanedText: fallbackText,
                    usedLLM: false,
                    providerIdentifier: nil,
                    fallbackReason: .deadlineExceeded,
                    asrMs: ctx.asrMs,
                    cleanupMs: cleanupMs,
                    totalMs: Int(Date().timeIntervalSince(ctx.operationStartedAt) * 1000),
                    deadlineExceeded: true
                )
                ctx.cleanupResult = fallbackResult
                delegate.lastTranscript = fallbackResult
            }
            guard let cleanupResult = ctx.cleanupResult else {
                log.error("processCapturedAudio: cleanup result missing")
                undoBookkeeping.clearInflight()
                await failPipeline(
                    message: "Transcript was empty",
                    stage: .cleanup,
                    reason: "cleanup_result_missing",
                    ctx: ctx
                )
                return
            }
            if cleanupResult.cleanedText.isEmpty {
                let fallbackText = cleanupResult.rawText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !fallbackText.isEmpty else {
                    let capturedDuration = ctx.captured.endedAt.timeIntervalSince(ctx.captured.startedAt)
                    let hasSpeechSignal = capturedDuration >= 1.0 && ctx.captured.peakLevel >= 0.02
                    if hasSpeechSignal {
                        log.error(
                            "processCapturedAudio: ASR empty despite speech signal — duration: \(capturedDuration, privacy: .public)s peak: \(ctx.captured.peakLevel, privacy: .public)"
                        )
                        undoBookkeeping.clearInflight()
                        await failPipeline(
                            message: "ASR returned empty transcript",
                            stage: .asr,
                            reason: "asr_empty_with_speech_signal",
                            ctx: ctx
                        )
                        return
                    }
                    log.error("processCapturedAudio: cleaned text was empty")
                    undoBookkeeping.clearInflight()
                    await failPipeline(
                        message: "Transcript was empty",
                        stage: .cleanup,
                        reason: "cleanup_empty_and_raw_empty",
                        ctx: ctx
                    )
                    return
                }
                log.warning("processCapturedAudio: cleanup empty; using raw ASR transcript fallback")
                let fallbackResult = VoiceCleanupResult(
                    rawText: cleanupResult.rawText,
                    cleanedText: fallbackText,
                    usedLLM: false,
                    providerIdentifier: cleanupResult.providerIdentifier,
                    fallbackReason: .emptyResponse,
                    asrMs: cleanupResult.asrMs,
                    cleanupMs: cleanupResult.cleanupMs,
                    totalMs: cleanupResult.totalMs,
                    deadlineExceeded: cleanupResult.deadlineExceeded
                )
                ctx.cleanupResult = fallbackResult
                delegate.lastTranscript = fallbackResult
            } else {
                delegate.lastTranscript = cleanupResult
            }

            // Plan 03 — reminder terminal phase.
            if delegate.activeIntent == .reminder, let writer = delegate.resolveReminderWriter() {
                try await delegate.finishReminderRun(
                    cleanedText: cleanupResult.cleanedText, writer: writer, generation: generation
                )
                return
            }

            // Phase 3 — Paste.
            delegate.state = .pasting
            hudPresenter?.showTranscribingPhase(.pasting)
            let pasteStartedAt = Date()
            let pasteCompleted = try await withThrowingTimeout(seconds: VoiceStageTimeouts.pasteSeconds) {
                try await self.makePastePhase().run(&ctx)
                return true
            } ?? false
            let pasteMs = Int(Date().timeIntervalSince(pasteStartedAt) * 1000)
            ctx.pasteMs = pasteMs
            guard pasteCompleted else {
                undoBookkeeping.clearInflight()
                await failPipeline(
                    message: "Paste timed out",
                    stage: .paste,
                    reason: "paste_timeout",
                    ctx: ctx
                )
                return
            }
            if let pasteResult = ctx.pasteResult, !pasteResult.insertedIntoActiveInput {
                undoBookkeeping.clearInflight()
                fail(pasteFailureMessage(for: pasteResult))
                return
            }

            // Phase 4 — Learning monitor (fire-and-forget).
            makeLearningPhase().run(ctx)

            guard isCurrentOperation(generation) else { return }
            logPipelineMetrics(ctx: ctx, cleanupMs: cleanupMs, pasteMs: pasteMs, delegate: delegate)
            delegate.state = .idle
            undoBookkeeping.clearInflight()
            delegate.inputSourceChangedDuringRun = false
            delegate.inputSourceAtRecordingStart = nil
            hudPresenter?.dismiss()
        } catch {
            guard isCurrentOperation(generation) else { return }
            undoBookkeeping.clearInflight()
            delegate.activeIntent = .dictation
            delegate.inputSourceChangedDuringRun = false
            delegate.inputSourceAtRecordingStart = nil
            let stage: VoiceTranscriptFailedStage
            switch delegate.state {
            case .pasting:
                stage = .paste
            case .transcribing:
                stage = .cleanup
            default:
                stage = .unknown
            }
            await failPipeline(
                message: error.localizedDescription,
                stage: stage,
                reason: "pipeline_exception",
                ctx: ctx
            )
        }
    }

    // MARK: - Undo

    /// Re-runs the transcribe + cleanup + paste flow against the audio that was
    /// in flight when the user last cancelled.
    func undoLastCancel() async {
        guard let undo = undoBookkeeping.consumePendingUndo() else { return }
        cancelUndoExpiration()
        delegate?.activeIntent = .dictation
        log.info("undoLastCancel — replay (asrPreset: \(undo.asrResult != nil, privacy: .public) age: \(Int(Date().timeIntervalSince(undo.cancelledAt) * 1000), privacy: .public)ms)")
        await processCapturedAudio(
            captured: undo.captured,
            presetASRResult: undo.asrResult,
            presetAppBundleID: undo.appBundleID
        )
    }

    func scheduleUndoExpiration() {
        cancelUndoExpiration()
        undoExpirationTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.undoWindowSeconds))
            await MainActor.run {
                self?.expirePendingUndo()
            }
        }
    }

    func cancelUndoExpiration() {
        undoExpirationTask?.cancel()
        undoExpirationTask = nil
    }

    func expirePendingUndo() {
        guard undoBookkeeping.hasPendingUndo else { return }
        log.info("undo window expired — dismissing cancelled pill")
        undoBookkeeping.expirePendingUndo()
        cancelUndoExpiration()
        hudPresenter?.dismiss()
    }

    func stopLearningMonitorTask() {
        monitorTask?.cancel()
        monitorTask = nil
    }

    // MARK: - Checkpoint helpers

    private func checkpoint(_ generation: Int, delegate: any VoicePipelineDelegate) -> Bool {
        let ok = isCurrentOperation(generation) && (delegate.state == .transcribing || delegate.state == .pasting)
        if !ok { undoBookkeeping.clearInflight() }
        return ok
    }

    func isCurrentOperation(_ generation: Int) -> Bool {
        generation == delegate?.operationGeneration
    }

    // MARK: - Phase builders

    private func makeCleanupPhase(bundleID: String?, generation: Int) -> CleanupPhase {
        let onThinkingProgress: (Double) -> Void = { [weak self] progress in
            guard let self, self.isCurrentOperation(generation) else { return }
            self.hudPresenter?.updateThinkingProgress(progress)
        }
        let (appCtx, globalCtx) = loadContexts(bundleID: bundleID)
        let recentExamplesContext = (appCtx?.enabled == false) ? nil : (appCtx ?? globalCtx)
        let dictionaryEntries = (try? dictionary?.list()) ?? []
        let recentExamples = loadRecentExamples(context: recentExamplesContext)
        return CleanupPhase(
            makePipeline: { [weak self] elapsed in
                self?.makeCleanupPipeline(elapsedBeforeCleanupSeconds: elapsed) ?? VoiceCleanupPipeline()
            },
            personalization: .init(
                dictionaryEntries: dictionaryEntries,
                appContext: appCtx,
                globalContext: globalCtx,
                recentExamples: recentExamples
            ),
            observer: cleanupObserver,
            onThinkingProgress: onThinkingProgress,
            log: log
        )
    }

    private func makePastePhase() -> PastePhase {
        PastePhase(
            saveTranscript: { [weak self] id, captured, result, text, bundleID, audioPath, status, failedStage, failureReason, retrySourceTranscriptID in
                guard let self else { throw NSError(domain: "VoicePipelineController", code: -1) }
                return try self.saveTranscript(
                    transcriptID: id, captured: captured, result: result,
                    cleanedText: text,
                    appBundleID: bundleID,
                    audioPath: audioPath,
                    status: status,
                    failedStage: failedStage,
                    failureReason: failureReason,
                    retrySourceTranscriptID: retrySourceTranscriptID
                )
            },
            persistAudio: { [weak self] captured, id, forceSave in
                self?.persistAudio(captured: captured, transcriptID: id, forceSave: forceSave)
            },
            saveTrainingExample: { [weak self] captured, result, text, id, bundleID, audioPath in
                self?.saveTrainingExample(
                    captured: captured, result: result, cleanedText: text,
                    transcriptID: id, appBundleID: bundleID, audioPath: audioPath
                )
            },
            paste: pasterOverride ?? { text, snapshot in await CursorPaster.paste(text, preferredTarget: snapshot) },
            snapshotFocused: snapshotFocusedOverride ?? { AXFocusedTextReader.snapshotFocused() },
            log: log
        )
    }

    private func makeLearningPhase() -> LearningPhase {
        LearningPhase(start: { [weak self] text, transcriptID, bundleID, isAutoSubmit, snapshot in
            if let override = self?.learningStarterOverride {
                override(text, transcriptID, bundleID, isAutoSubmit, snapshot)
            } else {
                self?.startLearningMonitor(
                    pastedText: text, transcriptID: transcriptID,
                    appBundleID: bundleID, isAutoSubmit: isAutoSubmit, snapshot: snapshot
                )
            }
        })
    }

    // MARK: - Cleanup pipeline factory

    func makeCleanupPipeline(elapsedBeforeCleanupSeconds: TimeInterval) -> VoiceCleanupPipeline {
        if let override = cleanupPipelineFactoryOverride {
            return override(elapsedBeforeCleanupSeconds)
        }
        do {
            let provider = try VoiceCleanupProviderFactory.makeProvider(
                settings: VoiceCleanupSettingsStore.load(),
                keyStore: cleanupKeyStore
            )
            guard let provider else {
                return VoiceCleanupPipeline()
            }
            let settings = VoiceCleanupSettingsStore.load()
            guard let timeout = VoiceCleanupLatencyBudget.remoteTimeout(
                policy: settings.latencyPolicy,
                elapsedBeforeCleanupSeconds: elapsedBeforeCleanupSeconds,
                configuredTimeoutSeconds: settings.normalizedTimeoutSeconds
            ) else {
                return VoiceCleanupPipeline(
                    provider: nil,
                    forcedFallbackReason: .deadlineExceeded,
                    forcedDeadlineExceeded: true
                )
            }
            return VoiceCleanupPipeline(
                provider: provider,
                timeout: timeout
            )
        } catch {
            log.error("Voice cleanup provider setup failed: \(error.localizedDescription, privacy: .public)")
            return VoiceCleanupPipeline()
        }
    }

    // MARK: - Persistence helpers

    // swiftlint:disable:next function_parameter_count
    func saveTranscript(
        transcriptID: String,
        captured: CapturedAudio,
        result: VoiceTranscriptionResult,
        cleanedText: String,
        appBundleID: String?,
        audioPath: String?,
        status: VoiceTranscriptStatus = .success,
        failedStage: VoiceTranscriptFailedStage? = nil,
        failureReason: String? = nil,
        retrySourceTranscriptID: String? = nil
    ) throws -> VoiceTranscript {
        try transcripts.save(VoiceTranscriptDraft(
            startedAt: captured.startedAt,
            endedAt: captured.endedAt,
            rawText: result.text,
            cleanedText: cleanedText,
            appBundleID: appBundleID,
            language: result.language,
            modelIdentifier: result.modelIdentifier,
            audioPath: audioPath,
            status: status,
            failedStage: failedStage,
            failureReason: failureReason,
            retrySourceTranscriptID: retrySourceTranscriptID
        ), existingID: transcriptID)
    }

    @discardableResult
    func persistAudio(captured: CapturedAudio, transcriptID: String, forceSave: Bool = false) -> String? {
        let shouldSave = personalizationSettings().saveTrainingExamplesEnabled
            || historySettings().saveAudio
            || forceSave
        guard shouldSave, let trainingExampleStore else { return nil }

        let sampleRate = max(1, Int(captured.sampleRate.rounded()))
        let wavData = VoiceAudioCodec.encodeWAV(samples: captured.samples, sampleRate: sampleRate)
        do {
            return try trainingExampleStore.saveEncryptedAudio(wavData, id: transcriptID)
        } catch {
            log.error("Voice audio persist failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func saveTrainingExample(
        captured: CapturedAudio,
        result: VoiceTranscriptionResult,
        cleanedText: String,
        transcriptID: String,
        appBundleID: String?,
        audioPath: String?
    ) {
        guard personalizationSettings().saveTrainingExamplesEnabled,
              let trainingExampleStore else { return }
        do {
            try trainingExampleStore.save(.init(
                transcriptID: transcriptID,
                rawText: result.text,
                cleanedText: cleanedText,
                finalText: cleanedText,
                appBundleID: appBundleID,
                language: result.language,
                modelIdentifier: result.modelIdentifier,
                audioPath: audioPath,
                quality: .medium,
                qualityReason: "awaiting_post_edit_verification"
            ))
        } catch {
            log.error("Voice training example save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func startLearningMonitor(
        pastedText: String,
        transcriptID: String?,
        appBundleID: String?,
        isAutoSubmit: Bool,
        snapshot: AXTargetSnapshot?
    ) {
        guard personalizationSettings().learnFromEditsEnabled else { return }
        guard let snapshot, let store = personalizationStore else { return }

        guard VoicePersonalizationPrivacyFilter.shouldCapture(snapshot.metadata) else { return }

        let learningBundleID = snapshot.metadata.bundleID ?? appBundleID

        if let bundleID = learningBundleID,
           let existing = try? store.fetchContext(bundleID: bundleID),
           !existing.enabled
        {
            return
        }

        let ctxID: String
        if let bundleID = learningBundleID {
            if let existing = try? store.fetchContext(bundleID: bundleID) {
                ctxID = existing.id
            } else {
                let displayName = NSRunningApplication
                    .runningApplications(withBundleIdentifier: bundleID)
                    .first?.localizedName ?? bundleID
                guard let created = try? store.upsertContext(
                    .init(bundleID: bundleID, displayName: displayName)
                ) else { return }
                ctxID = created.id
            }
        } else {
            if let global = try? store.fetchContext(bundleID: VoicePersonalizationContext.globalBundleID) {
                ctxID = global.id
            } else {
                guard let created = try? store.upsertContext(
                    .init(
                        bundleID: VoicePersonalizationContext.globalBundleID,
                        displayName: VoicePersonalizationContext.globalDisplayName
                    )
                ) else { return }
                ctxID = created.id
            }
        }

        let maxSamples = personalizationSettings().rollingCacheMaxSamples

        monitorTask = Task { [weak self] in
            guard let self else { return }
            let draft = await learningMonitor.observe(
                pastedText: pastedText,
                transcriptID: transcriptID,
                contextID: ctxID,
                isAutoSubmitContext: isAutoSubmit,
                snapshot: snapshot
            )
            guard let draft else {
                if let transcriptID {
                    try? trainingExampleStore?.updateQuality(
                        transcriptID: transcriptID,
                        quality: .medium,
                        qualityReason: "post_edit_verification_unavailable"
                    )
                }
                return
            }
            try? store.appendSample(draft)
            if let transcriptID, let finalText = draft.finalText {
                try? trainingExampleStore?.updateFinalText(
                    transcriptID: transcriptID,
                    finalText: finalText,
                    quality: draft.quality,
                    qualityReason: draft.qualityReason
                )
            }
            try? store.expireSamplesByCount(contextID: ctxID, max: maxSamples)
            try? store.expireSamplesByDate()
            await summarizer?.maybeRun(contextID: ctxID)
        }
    }

    // MARK: - Personalization helpers

    func loadContexts(bundleID: String?) -> (app: VoicePersonalizationContext?, global: VoicePersonalizationContext?) {
        let global = try? personalizationStore?.fetchContext(bundleID: VoicePersonalizationContext.globalBundleID)
        guard let bundleID else { return (nil, global) }
        let app = try? personalizationStore?.fetchContext(bundleID: bundleID)
        return (app, global)
    }

    func loadRecentExamples(context: VoicePersonalizationContext?) -> [(before: String, after: String)] {
        guard let ctxID = context?.id, let store = personalizationStore else { return [] }
        let pinned = (try? store.listPinnedExamples(contextID: ctxID)) ?? []
        let pinnedPairs = pinned.map { ($0.before, $0.after) }
        let samples = (try? store.listRecentSamples(contextID: ctxID, limit: 10)) ?? []
        let autoPairs = samples.map { ($0.before, $0.after) }
        return VoicePromptBuilder.cappedExamples(pinned: pinnedPairs, autoLearnedNewestFirst: autoPairs)
    }

    static func buildCleanupRequest(
        rawText: String,
        appBundleID: String?,
        language: VoiceLanguage,
        dictionaryEntries: [VoiceDictionaryEntry],
        appContext: VoicePersonalizationContext?,
        globalContext: VoicePersonalizationContext?,
        recentExamples: [(before: String, after: String)]
    ) -> VoiceCleanupRequest {
        if let appCtx = appContext, !appCtx.enabled {
            return VoiceCleanupRequest(
                rawText: rawText,
                appBundleID: appBundleID,
                language: language,
                dictionaryEntries: dictionaryEntries
            )
        }

        let effectiveCtx = appContext ?? globalContext

        return VoiceCleanupRequest(
            rawText: rawText,
            appBundleID: appBundleID,
            language: language,
            dictionaryEntries: dictionaryEntries,
            appInstructions: effectiveCtx?.customPromptOverride.flatMap { Self.trimmedOrNil($0) },
            personalStyleNotes: globalContext?.styleNotes.flatMap { Self.trimmedOrNil($0) },
            personalizationSummary: (appContext?.summary ?? globalContext?.summary).flatMap { Self.trimmedOrNil($0) },
            recentExamples: recentExamples
        )
    }

    private static func trimmedOrNil(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - Failure helpers

    private func fail(_ message: String) {
        log.error("Voice failed: \(message, privacy: .public)")
        delegate?.state = .error(message)
        hudPresenter?.showFailure(message) { [weak self] in
            self?.delegate?.state = .idle
        }
    }

    private func failPipeline(
        message: String,
        stage: VoiceTranscriptFailedStage,
        reason: String,
        ctx: VoicePipelineContext
    ) async {
        persistFailedTranscript(ctx: ctx, stage: stage, reason: reason)
        fail(message)
    }

    private func persistFailedTranscript(
        ctx: VoicePipelineContext,
        stage: VoiceTranscriptFailedStage,
        reason: String
    ) {
        let transcriptID = UUID().uuidString
        let audioPath = persistAudio(captured: ctx.captured, transcriptID: transcriptID, forceSave: true)
        let asrResult = ctx.asrResult ?? VoiceTranscriptionResult(
            text: "",
            language: .unknown,
            modelIdentifier: "unknown"
        )
        let cleaned = ctx.cleanupResult?.cleanedText ?? ""
        do {
            let saved = try saveTranscript(
                transcriptID: transcriptID,
                captured: ctx.captured,
                result: asrResult,
                cleanedText: cleaned,
                appBundleID: ctx.appBundleID,
                audioPath: audioPath,
                status: .failed,
                failedStage: stage,
                failureReason: reason,
                retrySourceTranscriptID: ctx.retrySourceTranscriptID
            )
            NotificationCenter.default.post(name: .voiceTranscriptAppended, object: saved.id)
            log.error(
                "voice_session_failed_saved id=\(saved.id, privacy: .public) stage=\(stage.rawValue, privacy: .public) reason=\(reason, privacy: .public) audioSaved=\(audioPath != nil, privacy: .public)"
            )
        } catch {
            log.error("voice_session_failed_saved failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func pasteFailureMessage(for result: CursorPaster.Result) -> String {
        switch result.failureReason {
        case .accessibilityPermissionMissing:
            return "Couldn't paste into active field. Accessibility permission is missing."
        case .targetNotWritable:
            return "Couldn't paste into active field. Target does not accept direct input."
        case .focusUnavailable:
            return "Couldn't paste into active field. No focused input was found."
        case .commandVUnavailable:
            return "Couldn't paste automatically. Text was copied to clipboard."
        case nil:
            return "Couldn't paste automatically. Text was copied to clipboard."
        }
    }

    // MARK: - Metrics

    private func logPipelineMetrics(
        ctx: VoicePipelineContext,
        cleanupMs: Int,
        pasteMs: Int,
        delegate: any VoicePipelineDelegate
    ) {
        let metrics = delegate.pendingPipelineMetrics
        delegate.pendingPipelineMetrics = nil
        let batchASRMs = ctx.asrMs.map(String.init) ?? "skipped"
        let chars = ctx.cleanupResult?.cleanedText.count ?? ctx.asrResult?.text.count ?? 0
        log.info(
            """
            voice.pipeline metrics recordingMs=\(metrics?.recordingMs ?? 0, privacy: .public) \
            liveFinishMs=\(metrics?.liveFinishMs ?? 0, privacy: .public) \
            liveUsed=\(metrics?.liveUsed == true, privacy: .public) \
            batchASRMs=\(batchASRMs, privacy: .public) \
            cleanupMs=\(ctx.cleanupMs ?? cleanupMs, privacy: .public) \
            pasteMs=\(ctx.pasteMs ?? pasteMs, privacy: .public) \
            stageLiveFinalizeMs=\(ctx.liveFinalizeMs ?? 0, privacy: .public) \
            chars=\(chars, privacy: .public) \
            peak=\(ctx.captured.peakLevel, privacy: .public)
            """
        )
    }

    // MARK: - Timeout utilities

    func withTimeout<T>(
        seconds: TimeInterval,
        operation: @escaping () async -> T
    ) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { await operation() }
            group.addTask {
                try? await Task.sleep(for: .milliseconds(Int64(seconds * 1000)))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    func withThrowingTimeout<T>(
        seconds: TimeInterval,
        operation: @escaping () async throws -> T
    ) async throws -> T? {
        try await withThrowingTaskGroup(of: T?.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try? await Task.sleep(for: .milliseconds(Int64(seconds * 1000)))
                return nil
            }
            let first = try await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}

// MARK: - Retry extension

extension VoicePipelineController {
    func retryTranscript(id: String) async throws -> VoiceTranscript {
        log.info("voice_retry_started source=\(id, privacy: .public)")
        let retryStartedAt = Date()
        guard let original = try transcripts.fetch(id: id) else {
            log.error("voice_retry_failed source=\(id, privacy: .public) stage=lookup reason=transcript_not_found")
            throw VoiceRetryError.transcriptNotFound
        }
        guard let audioPath = original.audioPath else {
            log.error("voice_retry_failed source=\(id, privacy: .public) stage=lookup reason=audio_missing")
            throw VoiceRetryError.audioMissing
        }
        guard let trainingExampleStore else {
            log.error("voice_retry_failed source=\(id, privacy: .public) stage=lookup reason=training_store_missing")
            throw VoiceRetryError.audioDecryptFailed
        }

        let wavData: Data
        do {
            wavData = try trainingExampleStore.loadEncryptedAudio(path: audioPath)
        } catch {
            log.error("voice_retry_failed source=\(id, privacy: .public) stage=audio reason=decrypt_failed")
            throw VoiceRetryError.audioDecryptFailed
        }
        let decoded: VoiceAudioCodec.DecodedAudio
        do {
            decoded = try VoiceAudioCodec.decodeWAV(wavData)
        } catch {
            log.error("voice_retry_failed source=\(id, privacy: .public) stage=audio reason=decode_failed")
            throw VoiceRetryError.audioDecodeFailed
        }

        let asrStartedAt = Date()
        let asrResult: VoiceTranscriptionResult
        do {
            guard let engine = delegate?.activeEngine else {
                throw VoiceRetryError.asrFailed
            }
            asrResult = try await engine.transcribe(
                samples: decoded.samples,
                sampleRate: Double(decoded.sampleRate),
                options: .default
            )
        } catch {
            log.error("voice_retry_failed source=\(id, privacy: .public) stage=asr reason=\(error.localizedDescription, privacy: .public)")
            throw VoiceRetryError.asrFailed
        }
        let asrMs = Int(Date().timeIntervalSince(asrStartedAt) * 1000)
        let dictionaryEntries = (try? dictionary?.list()) ?? []
        let (appCtx, globalCtx) = loadContexts(bundleID: original.appBundleID)
        let recentExamples = loadRecentExamples(context: appCtx ?? globalCtx)
        let cleanupRequest = Self.buildCleanupRequest(
            rawText: asrResult.text,
            appBundleID: original.appBundleID,
            language: asrResult.language,
            dictionaryEntries: dictionaryEntries,
            appContext: appCtx,
            globalContext: globalCtx,
            recentExamples: recentExamples
        )
        let cleanupStartedAt = Date()
        let rawCleanedResult = await makeCleanupPipeline(
            elapsedBeforeCleanupSeconds: Date().timeIntervalSince(retryStartedAt)
        ).clean(cleanupRequest)
        let cleanedResult = rawCleanedResult.withTimings(
            asrMs: asrMs,
            cleanupMs: Int(Date().timeIntervalSince(cleanupStartedAt) * 1000),
            totalMs: Int(Date().timeIntervalSince(retryStartedAt) * 1000)
        )
        let cleanedText = cleanedResult.cleanedText
        guard !cleanedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            log.error("voice_retry_failed source=\(id, privacy: .public) stage=cleanup reason=empty")
            throw VoiceRetryError.cleanupFailed
        }

        let saved = try transcripts.save(
            VoiceTranscriptDraft(
                startedAt: original.startedAt,
                endedAt: original.endedAt,
                rawText: asrResult.text,
                cleanedText: cleanedText,
                appBundleID: original.appBundleID,
                language: asrResult.language,
                modelIdentifier: asrResult.modelIdentifier,
                audioPath: audioPath,
                status: .retriedFrom,
                failedStage: nil,
                failureReason: nil,
                retrySourceTranscriptID: original.id
            )
        )
        log.info("voice_retry_succeeded source=\(id, privacy: .public) new=\(saved.id, privacy: .public)")
        NotificationCenter.default.post(name: .voiceTranscriptAppended, object: saved.id)
        return saved
    }
}
