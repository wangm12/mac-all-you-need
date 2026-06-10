import AppKit
import Carbon.HIToolbox
import Core
import Foundation
import Observation
import OSLog
import Platform

@MainActor
@Observable
final class VoiceCoordinator {
    enum State: Equatable {
        case idle
        case recording
        case transcribing
        case pasting
        case error(String)
    }

    private let audio = AudioCaptureService()
    private var engine: any VoiceTranscriptionEngine
    private let transcripts: VoiceTranscriptStore
    private let dictionary: VoiceDictionaryStore?
    private let personalizationStore: VoicePersonalizationStore?
    private let trainingExampleStore: VoiceTrainingExampleStore?
    private let personalizationSettings: () -> VoicePersonalizationSettings
    private let historySettings: () -> VoiceHistorySettings
    private let cleanupKeyStore: VoiceCleanupKeyStore
    private let learningMonitor: VoicePostEditLearningMonitor
    private let summarizer: VoicePersonalizationSummarizer?
    private let hud = MiniVoiceHUD()
    private let activation = VoiceActivationMonitor()
    let log = Logger(subsystem: "com.macallyouneed.voice", category: "coordinator")
    private var levelTask: Task<Void, Never>?
    private var liveFeedTask: Task<Void, Never>?
    private let liveFeed = VoiceLiveAudioFeed()
    private var liveSession: (any VoiceLiveTranscriptionSession)?
    private var liveSessionGeneration = 0
    private struct PendingPipelineMetrics {
        let recordingMs: Int
        let liveFinishMs: Int
        let liveUsed: Bool
    }
    private struct VoiceStageTimeouts {
        static let liveFinalizeSeconds: TimeInterval = 0.8
        static let cleanupSeconds: TimeInterval = 12.0
        static let pasteSeconds: TimeInterval = 2.0
    }

    private var pendingPipelineMetrics: PendingPipelineMetrics?
    private var isStoppingRecording = false
    private var monitorTask: Task<Void, Never>?
    private var errorDismissTask: Task<Void, Never>?
    private var cleanupSettings: VoiceCleanupSettings
    private var operationGeneration = 0
    private var activationMonitoringSuspended = false
    private var inputSourceChangedDuringRun = false
    private var inputSourceAtRecordingStart: String?
    private var inputSourceObserver: NSObjectProtocol?

    /// Test seams. Production callers go through the public `init` which sets
    /// these to live defaults (`CursorPaster.paste`, real AX reader, real
    /// cleanup factory, real learning monitor, no-op observer). Tests use the
    /// internal init below to swap them out.
    private let cleanupPipelineFactoryOverride: ((TimeInterval) -> VoiceCleanupPipeline)?
    private let pasterOverride: ((String, AXTargetSnapshot?) async -> CursorPaster.Result)?
    private let snapshotFocusedOverride: (() -> AXTargetSnapshot?)?
    private let learningStarterOverride: ((String, String?, String?, Bool, AXTargetSnapshot?) -> Void)?
    private let cleanupObserver: ((VoiceCleanupRequest) -> Void)?

    /// Holds the captured audio + ASR result for the in-flight dictation so
    /// the 5s Cancelled+Undo affordance can replay it without forcing the
    /// user to re-dictate. Exposed (internal) for tests.
    let undoBookkeeping = UndoContextBookkeeping()
    private var undoExpirationTask: Task<Void, Never>?
    private static let undoWindowSeconds: TimeInterval = 5

    /// Global Esc-key dispatch. Installed on start() so Esc/Return/numpad
    /// Enter can drive the HUD even when our app is not active.
    private let escKeyMonitor = EscKeyMonitor()

    private(set) var state: State = .idle
    private(set) var lastTranscript: VoiceCleanupResult?

    /// Voice → Reminders (Plan 03). When `activeIntent == .reminder` and a
    /// `reminderWriterOverride` (or the production writer) is present, the
    /// pipeline writes to Apple Reminders instead of pasting. The dictation
    /// path is unchanged when `activeIntent == .dictation`.
    var activeIntent: VoiceIntent = .dictation
    var reminderWriterOverride: (any RemindersWriter)?
    var remindersWorker: RemindersFeatureWorker?
    let reminderSettings: () -> ReminderSettings
    /// The reminder created on the most recent `.reminder` run, for UI/tests.
    var lastCreatedReminder: CreatedReminder?

    convenience init(
        transcripts: VoiceTranscriptStore,
        dictionary: VoiceDictionaryStore? = nil,
        personalizationStore: VoicePersonalizationStore? = nil,
        trainingExampleStore: VoiceTrainingExampleStore? = nil,
        personalizationSettings: @escaping () -> VoicePersonalizationSettings = { .default },
        engine: any VoiceTranscriptionEngine = VoiceLocalASREngine(),
        cleanupSettings: VoiceCleanupSettings = VoiceCleanupSettingsStore.load(),
        cleanupKeyStore: VoiceCleanupKeyStore = VoiceCleanupKeyStore(keychain: SystemKeychain()),
        learningMonitor: VoicePostEditLearningMonitor? = nil,
        summarizer: VoicePersonalizationSummarizer? = nil,
        historySettings: @escaping () -> VoiceHistorySettings = { .init() },
        reminderSettings: @escaping () -> ReminderSettings = { ReminderSettings.default }
    ) {
        self.init(
            transcripts: transcripts,
            dictionary: dictionary,
            personalizationStore: personalizationStore,
            trainingExampleStore: trainingExampleStore,
            personalizationSettings: personalizationSettings,
            engine: engine,
            cleanupSettings: cleanupSettings,
            cleanupKeyStore: cleanupKeyStore,
            learningMonitor: learningMonitor,
            summarizer: summarizer,
            historySettings: historySettings,
            reminderSettings: reminderSettings,
            cleanupPipelineFactory: nil,
            paster: nil,
            snapshotFocused: nil,
            learningStarter: nil,
            cleanupObserver: nil
        )
    }

    /// Internal init seam used by `VoiceCoordinatorPipelineCallSequenceTests`
    /// to inject the cleanup pipeline factory, paster, AX snapshotter, and
    /// learning monitor starter without standing up the real CursorPaster /
    /// AX / cloud LLM dependencies. All overrides default to nil — when nil
    /// the production path is used.
    // swiftlint:disable:next function_parameter_count
    init(
        transcripts: VoiceTranscriptStore,
        dictionary: VoiceDictionaryStore? = nil,
        personalizationStore: VoicePersonalizationStore? = nil,
        trainingExampleStore: VoiceTrainingExampleStore? = nil,
        personalizationSettings: @escaping () -> VoicePersonalizationSettings = { .default },
        engine: any VoiceTranscriptionEngine = VoiceLocalASREngine(),
        cleanupSettings: VoiceCleanupSettings = VoiceCleanupSettingsStore.load(),
        cleanupKeyStore: VoiceCleanupKeyStore = VoiceCleanupKeyStore(keychain: SystemKeychain()),
        learningMonitor: VoicePostEditLearningMonitor? = nil,
        summarizer: VoicePersonalizationSummarizer? = nil,
        historySettings: @escaping () -> VoiceHistorySettings = { .init() },
        reminderSettings: @escaping () -> ReminderSettings = { ReminderSettings.default },
        cleanupPipelineFactory: ((TimeInterval) -> VoiceCleanupPipeline)?,
        paster: ((String, AXTargetSnapshot?) async -> CursorPaster.Result)?,
        snapshotFocused: (() -> AXTargetSnapshot?)?,
        learningStarter: ((String, String?, String?, Bool, AXTargetSnapshot?) -> Void)?,
        cleanupObserver: ((VoiceCleanupRequest) -> Void)?
    ) {
        self.transcripts = transcripts
        self.dictionary = dictionary
        self.personalizationStore = personalizationStore
        self.trainingExampleStore = trainingExampleStore
        self.personalizationSettings = personalizationSettings
        self.engine = engine
        self.cleanupSettings = cleanupSettings
        self.cleanupKeyStore = cleanupKeyStore
        self.learningMonitor = learningMonitor ?? VoicePostEditLearningMonitor()
        self.summarizer = summarizer
        self.historySettings = historySettings
        self.reminderSettings = reminderSettings
        cleanupPipelineFactoryOverride = cleanupPipelineFactory
        pasterOverride = paster
        snapshotFocusedOverride = snapshotFocused
        learningStarterOverride = learningStarter
        self.cleanupObserver = cleanupObserver
        activation.onPress = { [weak self] in Task { @MainActor in await self?.handleActivationPress() } }
        activation.onRelease = { [weak self] in Task { @MainActor in await self?.handleActivationRelease() } }
        escKeyMonitor.onEsc = { [weak self] in self?.handleEscKey() }
        escKeyMonitor.onReturn = { [weak self] in self?.handleEnterKey() }
    }

    func start() {
        guard !activationMonitoringSuspended else { return }
        do {
            try activation.start(settings: VoiceActivationSettingsStore.load())
        } catch {
            log.error("Voice activation failed: \(error.localizedDescription, privacy: .public)")
        }
        // Load the configured ASR model only if it is already installed.
        // Downloads are explicit user actions from Voice setup/model management.
        if let local = engine as? VoiceLocalASREngine {
            Task.detached { await local.warmup() }
        } else if let qwen = engine as? Qwen3Engine {
            Task.detached { await qwen.warmup() }
        }
        escKeyMonitor.install()
        installInputSourceObserverIfNeeded()
    }

    func applyActivationSettings(_ settings: VoiceActivationSettings) throws {
        guard !activationMonitoringSuspended else { return }
        try activation.start(settings: settings)
    }

    func suspendActivationMonitoring() {
        guard !activationMonitoringSuspended else { return }
        activationMonitoringSuspended = true
        activation.stop()
    }

    func resumeActivationMonitoring() {
        guard activationMonitoringSuspended else { return }
        activationMonitoringSuspended = false
        start()
    }

    func applyCleanupSettings(_ settings: VoiceCleanupSettings) {
        cleanupSettings = settings
    }

    /// Hot-swaps the ASR engine so provider changes in Settings take effect
    /// on the next dictation without requiring an app restart.
    func applyASRProvider(_ providerKind: VoiceASRProviderKind, keychain: KeychainBackend) {
        switch providerKind {
        case .local:
            let local = VoiceLocalASREngine()
            engine = local
            // Only warm an already-installed model. Never download from provider switching.
            Task.detached { await local.warmup() }
        case .groq:
            let keyStore = GroqASRKeyStore(keychain: keychain)
            engine = GroqASREngine(
                settings: { GroqASRSettingsStore.load() },
                keyStore: keyStore
            )
        case .elevenLabs, .openAITranscribe, .deepgram:
            let keyStore = VoiceCloudASRKeyStore(keychain: keychain)
            engine = VoiceCloudASREngine(
                providerKind: providerKind,
                settings: { VoiceCloudASRSettingsStore.load() },
                keyStore: keyStore
            )
        }
    }

    func stop() {
        operationGeneration += 1
        cancelErrorDismissTask()
        activationMonitoringSuspended = false
        activation.stop()
        levelTask?.cancel()
        levelTask = nil
        liveFeedTask?.cancel()
        liveFeedTask = nil
        Task { await cancelLiveASR() }
        monitorTask?.cancel()
        monitorTask = nil
        _ = audio.stop()
        uninstallInputSourceObserver()
        hud.dismiss()
    }

    func startRecording() async {
        // Cancel any in-flight post-edit monitor from the previous dictation.
        monitorTask?.cancel()
        monitorTask = nil
        // If a Cancelled+Undo pill is still up from a previous session, clear
        // it now so we never accumulate a stale undo context behind a fresh
        // recording (Gap D in the interaction audit).
        if undoBookkeeping.hasPendingUndo {
            expirePendingUndo()
        }

        guard state == .idle else {
            log.warning("startRecording called but state is \(String(describing: self.state), privacy: .public)")
            return
        }
        lastTranscript = nil
        inputSourceAtRecordingStart = currentInputSourceName()
        inputSourceChangedDuringRun = false
        Task {
            if let local = engine as? VoiceLocalASREngine {
                await local.warmup()
            }
        }
        guard await audio.requestPermission() else {
            log.error("startRecording: microphone permission denied")
            fail("Microphone permission denied")
            return
        }
        do {
            try audio.start()
            operationGeneration += 1
            state = .recording
            log.info("recording started — generation: \(self.operationGeneration, privacy: .public)")
            hud.show(.recording(level: 0), onCancel: makeCancelAction(), onPrimary: makeCancelAction())
            startLevelUpdates()
            await beginLiveASR(generation: operationGeneration)
        } catch {
            log.error("audio start failed: \(error.localizedDescription, privacy: .public)")
            fail(error.localizedDescription)
        }
    }

    func stopRecordingAndPaste() async {
        guard state == .recording else { return }
        guard !isStoppingRecording else { return }
        isStoppingRecording = true
        defer { isStoppingRecording = false }
        showTranscribingPhase(.finalizing)
        levelTask?.cancel()
        levelTask = nil
        liveFeedTask?.cancel()
        liveFeedTask = nil

        let liveGeneration = liveSessionGeneration
        if let snapshot = audio.liveFeedSnapshot(),
           let session = liveSession,
           liveGeneration == liveSessionGeneration
        {
            try? await liveFeed.drain(snapshot: snapshot, into: session)
        }

        guard let captured = audio.stop(), captured.samples.count > 800 else {
            await cancelLiveASR()
            log.error("stopRecordingAndPaste: insufficient audio captured (need >800 samples)")
            fail("No usable audio captured")
            return
        }

        let liveFinishStartedAt = Date()
        let presetASRResult = (await withTimeout(seconds: VoiceStageTimeouts.liveFinalizeSeconds) {
            await self.finishLiveASRIfEligible(
            captured: captured,
            generation: liveGeneration
        )
        }) ?? nil
        if presetASRResult == nil {
            log.info("live ASR finalize timed out or empty — continuing with batch ASR")
        }
        pendingPipelineMetrics = PendingPipelineMetrics(
            recordingMs: Int(captured.endedAt.timeIntervalSince(captured.startedAt) * 1000),
            liveFinishMs: Int(Date().timeIntervalSince(liveFinishStartedAt) * 1000),
            liveUsed: presetASRResult != nil
        )

        log.info("stopRecordingAndPaste — samples: \(captured.samples.count, privacy: .public) sampleRate: \(captured.sampleRate, privacy: .public) peak: \(captured.peakLevel, privacy: .public) liveASR: \(presetASRResult != nil, privacy: .public)")
        await processCapturedAudio(
            captured: captured,
            presetASRResult: presetASRResult,
            presetAppBundleID: nil
        )
    }

    /// Drives the ASR → cleanup → paste → save → learning pipeline against
    /// `captured` audio. Internal (not private) so the spine test can drive
    /// it end-to-end with injected phase dependencies. Shared by the live
    /// `stopRecordingAndPaste` entry and by `undoLastCancel`, which calls in
    /// again with `presetASRResult` populated so the ASR phase is skipped.
    func processCapturedAudio(
        captured: CapturedAudio,
        presetASRResult: VoiceTranscriptionResult?,
        presetAppBundleID: String?,
        retrySourceTranscriptID: String? = nil
    ) async {
        operationGeneration += 1
        let generation = operationGeneration
        let appBundleID = presetAppBundleID ?? NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        state = .transcribing
        isStoppingRecording = false
        undoBookkeeping.setInflight(captured: captured, appBundleID: appBundleID, asrResult: presetASRResult)
        showTranscribingPhase(presetASRResult == nil ? .asr : .cleanup(progress: 0))
        log.info("ASR start — app: \(appBundleID ?? "nil", privacy: .public) presetASR: \(presetASRResult != nil, privacy: .public)")

        var ctx = VoicePipelineContext(
            captured: captured,
            presetASRResult: presetASRResult,
            appBundleID: appBundleID,
            generation: generation,
            retrySourceTranscriptID: retrySourceTranscriptID,
            operationStartedAt: Date()
        )
        ctx.liveFinalizeMs = pendingPipelineMetrics?.liveFinishMs

        do {
            // Phase 1 — ASR.
            try await ASRPhase(engine: engine, log: log).run(&ctx)
            guard checkpoint(generation) else { return }
            if presetASRResult == nil, let asr = ctx.asrResult {
                undoBookkeeping.setInflightASRResult(asr)
            }

            // Plan 03 — promote to reminder intent when the transcript opens
            // with a spoken reminder prefix (gated by settings; hotkey intent
            // is never demoted). See VoiceCoordinator+Reminders.
            maybePromoteToReminderIntent(rawText: ctx.asrResult?.text)

            // Phase 2 — Cleanup.
            showTranscribingPhase(.cleanup(progress: 0))
            let cleanupStartedAt = Date()
            let cleanupCompleted = await withTimeout(seconds: VoiceStageTimeouts.cleanupSeconds) {
                await self.makeCleanupPhase(bundleID: appBundleID, generation: generation).run(&ctx)
                return true
            } ?? false
            let cleanupMs = Int(Date().timeIntervalSince(cleanupStartedAt) * 1000)
            ctx.cleanupMs = cleanupMs
            guard checkpoint(generation) else { return }
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
                lastTranscript = fallbackResult
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
                lastTranscript = fallbackResult
            } else {
                lastTranscript = cleanupResult
            }

            // Plan 03 — reminder terminal phase replaces paste for the reminder
            // intent (never injects into the focused app). See the extension.
            if activeIntent == .reminder, let writer = resolveReminderWriter() {
                try await finishReminderRun(
                    cleanedText: cleanupResult.cleanedText, writer: writer, generation: generation
                )
                return
            }

            // Phase 3 — Paste (also saves transcript + training example).
            state = .pasting
            showTranscribingPhase(.pasting)
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
            logPipelineMetrics(
                ctx: ctx,
                cleanupMs: cleanupMs,
                pasteMs: pasteMs
            )
            state = .idle
            undoBookkeeping.clearInflight()
            inputSourceChangedDuringRun = false
            inputSourceAtRecordingStart = nil
            hud.dismiss()
        } catch {
            guard isCurrentOperation(generation) else { return }
            undoBookkeeping.clearInflight()
            activeIntent = .dictation
            inputSourceChangedDuringRun = false
            inputSourceAtRecordingStart = nil
            let stage: VoiceTranscriptFailedStage
            switch state {
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

    /// Returns false (and clears the inflight context) when this operation has
    /// been superseded — coordinator should bail out of the pipeline.
    private func checkpoint(_ generation: Int) -> Bool {
        let ok = isCurrentOperation(generation) && (state == .transcribing || state == .pasting)
        if !ok { undoBookkeeping.clearInflight() }
        return ok
    }

    /// Builds a CleanupPhase wired to the current personalization context for
    /// `bundleID`. Extracted so processCapturedAudio stays orchestration-only.
    private func makeCleanupPhase(bundleID: String?, generation: Int) -> CleanupPhase {
        let onThinkingProgress: (Double) -> Void = { [weak self] progress in
            guard let self, self.isCurrentOperation(generation) else { return }
            self.hud.updateThinkingProgress(progress)
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
                guard let self else { throw NSError(domain: "VoiceCoordinator", code: -1) }
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

    /// Re-runs the transcribe + cleanup + paste flow against the audio that was
    /// in flight when the user last cancelled. If the cancel happened after
    /// ASR completed, this skips ASR and replays just the cleanup pass.
    func undoLastCancel() async {
        guard let undo = undoBookkeeping.consumePendingUndo() else { return }
        cancelUndoExpiration()
        activeIntent = .dictation
        log.info("undoLastCancel — replay (asrPreset: \(undo.asrResult != nil, privacy: .public) age: \(Int(Date().timeIntervalSince(undo.cancelledAt) * 1000), privacy: .public)ms)")
        await processCapturedAudio(
            captured: undo.captured,
            presetASRResult: undo.asrResult,
            presetAppBundleID: undo.appBundleID
        )
    }

    private func scheduleUndoExpiration() {
        cancelUndoExpiration()
        undoExpirationTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.undoWindowSeconds))
            await MainActor.run {
                self?.expirePendingUndo()
            }
        }
    }

    private func cancelUndoExpiration() {
        undoExpirationTask?.cancel()
        undoExpirationTask = nil
    }

    private func expirePendingUndo() {
        guard undoBookkeeping.hasPendingUndo else { return }
        log.info("undo window expired — dismissing cancelled pill")
        undoBookkeeping.expirePendingUndo()
        cancelUndoExpiration()
        hud.dismiss()
    }

    func cancelCurrentOperation() {
        guard state == .recording || state == .transcribing else { return }
        let wasRecording = state == .recording
        let savedTranscribingCaptured = undoBookkeeping.inflightCaptured
        let savedASRResult = undoBookkeeping.inflightASRResult
        let savedAppBundleID = undoBookkeeping.inflightAppBundleID

        operationGeneration += 1
        activeIntent = .dictation
        levelTask?.cancel()
        levelTask = nil
        liveFeedTask?.cancel()
        liveFeedTask = nil
        Task { await self.cancelLiveASR() }
        monitorTask?.cancel()
        monitorTask = nil
        // During .recording the mic is still open; stop() returns the audio we
        // captured so far so a recording-time cancel can also offer Undo.
        // During .transcribing the mic was already stopped — stop() returns nil
        // and we fall back to the inflight context.
        let stoppedAudio = audio.stop()
        state = .idle
        undoBookkeeping.clearInflight()

        let undoCaptured: CapturedAudio?
        let undoAppBundleID: String?
        let undoASRResult: VoiceTranscriptionResult?
        if wasRecording {
            undoCaptured = (stoppedAudio?.samples.count ?? 0) > 800 ? stoppedAudio : nil
            undoAppBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            undoASRResult = nil
        } else {
            undoCaptured = savedTranscribingCaptured
            undoAppBundleID = savedAppBundleID
            undoASRResult = savedASRResult
        }

        if let captured = undoCaptured {
            log.info("cancelCurrentOperation — offering undo (wasRecording: \(wasRecording, privacy: .public) asrPreset: \(undoASRResult != nil, privacy: .public))")
            undoBookkeeping.recordCancel(
                captured: captured,
                asrResult: undoASRResult,
                appBundleID: undoAppBundleID
            )
            hud.show(.cancelled,
                     onCancel: makeDismissUndoAction(),
                     onPrimary: makeUndoAction())
            scheduleUndoExpiration()
        } else {
            log.info("cancelCurrentOperation — no usable audio, dismissing without undo")
            hud.dismiss()
        }
    }

    // swiftlint:disable:next function_parameter_count
    private func saveTranscript(
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

    private func loadContexts(bundleID: String?) -> (app: VoicePersonalizationContext?, global: VoicePersonalizationContext?) {
        let global = try? personalizationStore?.fetchContext(bundleID: VoicePersonalizationContext.globalBundleID)
        guard let bundleID else { return (nil, global) }
        // Return raw app context regardless of enabled — callers decide how to interpret
        // a disabled context. buildCleanupRequest treats disabled = full personalization opt-out.
        let app = try? personalizationStore?.fetchContext(bundleID: bundleID)
        return (app, global)
    }

    private func loadRecentExamples(context: VoicePersonalizationContext?) -> [(before: String, after: String)] {
        guard let ctxID = context?.id, let store = personalizationStore else { return [] }
        let pinned = (try? store.listPinnedExamples(contextID: ctxID)) ?? []
        let pinnedPairs = pinned.map { ($0.before, $0.after) }
        let samples = (try? store.listRecentSamples(contextID: ctxID, limit: 10)) ?? []
        let autoPairs = samples.map { ($0.before, $0.after) }
        return VoicePromptBuilder.cappedExamples(pinned: pinnedPairs, autoLearnedNewestFirst: autoPairs)
    }

    /// Builds the cleanup request, honoring disabled-app-context as a full personalization
    /// opt-out (no global fallback for any field). Internal+static so it is testable in
    /// isolation without spinning up the full coordinator.
    static func buildCleanupRequest(
        rawText: String,
        appBundleID: String?,
        language: VoiceLanguage,
        dictionaryEntries: [VoiceDictionaryEntry],
        appContext: VoicePersonalizationContext?,
        globalContext: VoicePersonalizationContext?,
        recentExamples: [(before: String, after: String)]
    ) -> VoiceCleanupRequest {
        // If the user explicitly disabled personalization for this app, skip ALL
        // personalization fields. No global fallback. The disable toggle is a hard
        // opt-out for both learning and prompt enrichment.
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

    /// Internal for testing via VoiceCoordinatorPersonalizationTests.
    func startLearningMonitor(
        pastedText: String,
        transcriptID: String?,
        appBundleID: String?,
        isAutoSubmit: Bool,
        snapshot: AXTargetSnapshot?
    ) {
        guard personalizationSettings().learnFromEditsEnabled else { return }
        guard let snapshot, let store = personalizationStore else { return }

        // C1: enforce privacy filter BEFORE starting the monitor.
        guard VoicePersonalizationPrivacyFilter.shouldCapture(snapshot.metadata) else { return }

        // B-3: prefer the snapshot's bundleID for context resolution. The captured
        // appBundleID was taken before cleanup; if the user switched apps during the
        // (potentially multi-second) cloud LLM round-trip, the paste — and the edit —
        // happen in the new app. Sample attribution must follow where the paste landed.
        let learningBundleID = snapshot.metadata.bundleID ?? appBundleID

        // I3: if an app context exists and the user has disabled it, respect that.
        // Do NOT fall through to global when the user explicitly opted this app out.
        if let bundleID = learningBundleID,
           let existing = try? store.fetchContext(bundleID: bundleID),
           !existing.enabled
        {
            return
        }

        // C2: ensure a context row exists for this app. Create on first use.
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
            // No app bundle ID — fall back to global, ensuring it exists.
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
            // I4: enforce retention limits on every append so they hold even when
            // the LLM provider is unavailable and the summarizer never fires.
            try? store.expireSamplesByCount(contextID: ctxID, max: maxSamples)
            try? store.expireSamplesByDate()
            await summarizer?.maybeRun(contextID: ctxID)
        }
    }

    // swiftlint:disable:next function_parameter_count
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

    /// Internal for testing — call before building VoiceTranscriptDraft so audioPath is set on save.
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

    private static func trimmedOrNil(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func makeCleanupPipeline(elapsedBeforeCleanupSeconds: TimeInterval) -> VoiceCleanupPipeline {
        if let override = cleanupPipelineFactoryOverride {
            return override(elapsedBeforeCleanupSeconds)
        }
        do {
            let provider = try VoiceCleanupProviderFactory.makeProvider(
                settings: cleanupSettings,
                keyStore: cleanupKeyStore
            )
            guard let provider else {
                return VoiceCleanupPipeline()
            }
            guard let timeout = VoiceCleanupLatencyBudget.remoteTimeout(
                policy: cleanupSettings.latencyPolicy,
                elapsedBeforeCleanupSeconds: elapsedBeforeCleanupSeconds,
                configuredTimeoutSeconds: cleanupSettings.normalizedTimeoutSeconds
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

    private func handleActivationPress() async {
        if state == .recording {
            // Immediate visual acknowledgement on hotkey press so users do not
            // re-press while stop/finish work is still spinning.
            showTranscribingPhase(.finalizing)
            await stopRecordingAndPaste()
        } else if case .error = state {
            // Hotkey should recover immediately from terminal error pills
            // instead of waiting for the 2s auto-dismiss timeout.
            performDismiss()
            activeIntent = .dictation
            await startRecording()
        } else if state == .transcribing || state == .pasting {
            // Ignore toggle presses while the pipeline is running.
            return
        } else {
            // The dictation hotkey always dictates — never inherits a stale
            // reminder intent from a previously cancelled reminder run.
            activeIntent = .dictation
            await startRecording()
        }
    }

    private func handleActivationRelease() async {
        guard state == .recording else { return }
        await stopRecordingAndPaste()
    }

    private func beginLiveASR(generation: Int) async {
        guard let liveEngine = engine as? VoiceLiveTranscriptionEngine else { return }
        do {
            let session = try await liveEngine.makeLiveSession(options: .default)
            liveSession = session
            liveSessionGeneration = generation
            await liveFeed.reset()
            liveFeedTask = Task { [weak self] in
                guard let self else { return }
                while !Task.isCancelled {
                    guard self.operationGeneration == generation, self.state == .recording else { return }
                    guard let snapshot = self.audio.liveFeedSnapshot() else {
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

    private func finishLiveASRIfEligible(
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
            if engine is VoiceLocalASREngine,
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

    private func cancelLiveASR() async {
        liveFeedTask?.cancel()
        liveFeedTask = nil
        if let session = liveSession {
            await session.cancel()
        }
        liveSession = nil
        await liveFeed.reset()
    }

    private func logPipelineMetrics(
        ctx: VoicePipelineContext,
        cleanupMs: Int,
        pasteMs: Int
    ) {
        let metrics = pendingPipelineMetrics
        pendingPipelineMetrics = nil
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

    private func startLevelUpdates() {
        levelTask?.cancel()
        levelTask = Task { @MainActor in
            while !Task.isCancelled, state == .recording {
                hud.show(.recording(level: audio.peakLevel), onCancel: makeCancelAction(), onPrimary: makeCancelAction())
                try? await Task.sleep(for: .milliseconds(VoiceLevelSampling.intervalMilliseconds))
            }
        }
    }

    private func fail(_ message: String) {
        cancelErrorDismissTask()
        levelTask?.cancel()
        levelTask = nil
        _ = audio.stop()
        log.error("Voice failed: \(message, privacy: .public)")
        state = .error(message)
        hud.show(.error(message), onPrimary: makeDismissAction())
        errorDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self else { return }
            if case .error = self.state {
                self.state = .idle
                self.hud.dismiss()
            }
            self.errorDismissTask = nil
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

    func isCurrentOperation(_ generation: Int) -> Bool {
        generation == operationGeneration
    }

    /// Plan 03 — terminal teardown shared by the reminder path (see
    /// VoiceCoordinator+Reminders). Mirrors the dictation happy-path teardown.
    func teardownAfterReminderRun() {
        state = .idle
        undoBookkeeping.clearInflight()
        hud.dismiss()
        activeIntent = .dictation
    }

    private func makeCancelAction() -> () -> Void {
        { [weak self] in Task { @MainActor in self?.cancelCurrentOperation() } }
    }

    private func showTranscribingPhase(_ phase: MiniVoiceHUD.TranscribingSubphase) {
        log.info("voice.stage — \(String(describing: phase), privacy: .public)")
        hud.show(.transcribing(phase), onCancel: makeCancelAction(), onPrimary: makeCancelAction())
    }

    private func installInputSourceObserverIfNeeded() {
        guard inputSourceObserver == nil else { return }
        inputSourceObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.HIToolbox.selectedKeyboardInputSourceChanged"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleInputSourceChanged()
            }
        }
    }

    private func uninstallInputSourceObserver() {
        guard let inputSourceObserver else { return }
        DistributedNotificationCenter.default().removeObserver(inputSourceObserver)
        self.inputSourceObserver = nil
    }

    private func handleInputSourceChanged() {
        guard state == .recording || state == .transcribing || state == .pasting else { return }
        let current = currentInputSourceName()
        guard let start = inputSourceAtRecordingStart,
              let current,
              current != start
        else { return }
        guard !inputSourceChangedDuringRun else { return }
        inputSourceChangedDuringRun = true
        log.warning("input source changed during dictation — from: \(start, privacy: .public) to: \(current, privacy: .public)")
    }

    private func currentInputSourceName() -> String? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return nil }
        let property = TISGetInputSourceProperty(source, kTISPropertyLocalizedName)
        return property as? String
    }

    private func pasteFailureMessage(for result: CursorPaster.Result) -> String {
        switch result.failureReason {
        case .accessibilityPermissionMissing:
            return "Couldn’t paste into active field. Accessibility permission is missing."
        case .targetNotWritable:
            return "Couldn’t paste into active field. Target does not accept direct input."
        case .focusUnavailable:
            return "Couldn’t paste into active field. No focused input was found."
        case .commandVUnavailable:
            return "Couldn’t paste automatically. Text was copied to clipboard."
        case nil:
            return "Couldn’t paste automatically. Text was copied to clipboard."
        }
    }

    private func withTimeout<T>(
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

    private func withThrowingTimeout<T>(
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

    private func makeDismissAction() -> () -> Void {
        { [weak self] in
            Task { @MainActor in
                self?.performDismiss()
            }
        }
    }

    private func performDismiss() {
        operationGeneration += 1
        cancelErrorDismissTask()
        state = .idle
        hud.dismiss()
    }

    private func cancelErrorDismissTask() {
        errorDismissTask?.cancel()
        errorDismissTask = nil
    }

    private func makeUndoAction() -> () -> Void {
        { [weak self] in
            Task { @MainActor in
                await self?.undoLastCancel()
            }
        }
    }

    private func makeDismissUndoAction() -> () -> Void {
        { [weak self] in
            Task { @MainActor in
                self?.expirePendingUndo()
            }
        }
    }

    private func handleEscKey() {
        if state == .recording || state == .transcribing {
            log.info("esc — cancelling current operation (state: \(String(describing: self.state), privacy: .public))")
            cancelCurrentOperation()
        } else if undoBookkeeping.hasPendingUndo {
            log.info("esc — dismissing undo offer")
            expirePendingUndo()
        } else if hud.isVisible {
            log.info("esc — dismissing visible HUD")
            performDismiss()
        }
        // else: no HUD up and nothing to cancel — ignore Esc so we don't
        // interfere with other apps' Esc handlers.
    }

    private func handleEnterKey() {
        // Only fires when the Cancelled+Undo pill is on screen. Acts as a
        // keyboard shortcut for the on-screen Undo button.
        guard undoBookkeeping.hasPendingUndo else { return }
        log.info("enter — triggering undo")
        Task { @MainActor in
            await self.undoLastCancel()
        }
    }
}

enum VoiceLevelSampling {
    static let intervalMilliseconds = 25
}

extension Notification.Name {
    static let voiceTranscriptAppended = Notification.Name("com.macallyouneed.voiceTranscriptAppended")
}

enum VoiceRetryError: Error, Equatable {
    case transcriptNotFound
    case audioMissing
    case audioDecryptFailed
    case audioDecodeFailed
    case asrFailed
    case cleanupFailed
}

extension VoiceCoordinator {
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
