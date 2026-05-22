import AppKit
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
    private let log = Logger(subsystem: "com.macallyouneed.voice", category: "coordinator")
    private var levelTask: Task<Void, Never>?
    private var monitorTask: Task<Void, Never>?
    private var cleanupSettings: VoiceCleanupSettings
    private var operationGeneration = 0
    private var activationMonitoringSuspended = false

    /// Test seams. Production callers go through the public `init` which sets
    /// these to live defaults (`CursorPaster.paste`, real AX reader, real
    /// cleanup factory, real learning monitor, no-op observer). Tests use the
    /// internal init below to swap them out.
    private let cleanupPipelineFactoryOverride: ((TimeInterval) -> VoiceCleanupPipeline)?
    private let pasterOverride: ((String) async -> CursorPaster.Result)?
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
        historySettings: @escaping () -> VoiceHistorySettings = { .init() }
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
        cleanupPipelineFactory: ((TimeInterval) -> VoiceCleanupPipeline)?,
        paster: ((String) async -> CursorPaster.Result)?,
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
        activationMonitoringSuspended = false
        activation.stop()
        levelTask?.cancel()
        levelTask = nil
        monitorTask?.cancel()
        monitorTask = nil
        _ = audio.stop()
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
        } catch {
            log.error("audio start failed: \(error.localizedDescription, privacy: .public)")
            fail(error.localizedDescription)
        }
    }

    func stopRecordingAndPaste() async {
        guard state == .recording else { return }
        levelTask?.cancel()
        levelTask = nil

        guard let captured = audio.stop(), captured.samples.count > 800 else {
            log.error("stopRecordingAndPaste: insufficient audio captured (need >800 samples)")
            fail("No usable audio captured")
            return
        }

        log.info("stopRecordingAndPaste — samples: \(captured.samples.count, privacy: .public) sampleRate: \(captured.sampleRate, privacy: .public) peak: \(captured.peakLevel, privacy: .public)")
        await processCapturedAudio(captured: captured, presetASRResult: nil, presetAppBundleID: nil)
    }

    /// Drives the ASR → cleanup → paste → save → learning pipeline against
    /// `captured` audio. Internal (not private) so the spine test can drive
    /// it end-to-end with injected phase dependencies. Shared by the live
    /// `stopRecordingAndPaste` entry and by `undoLastCancel`, which calls in
    /// again with `presetASRResult` populated so the ASR phase is skipped.
    func processCapturedAudio(
        captured: CapturedAudio,
        presetASRResult: VoiceTranscriptionResult?,
        presetAppBundleID: String?
    ) async {
        operationGeneration += 1
        let generation = operationGeneration
        let appBundleID = presetAppBundleID ?? NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        state = .transcribing
        undoBookkeeping.setInflight(captured: captured, appBundleID: appBundleID, asrResult: presetASRResult)
        hud.show(presetASRResult == nil ? .transcribing : .thinking,
                 onCancel: makeCancelAction(),
                 onPrimary: makeCancelAction())
        log.info("ASR start — app: \(appBundleID ?? "nil", privacy: .public) presetASR: \(presetASRResult != nil, privacy: .public)")

        var ctx = VoicePipelineContext(
            captured: captured,
            presetASRResult: presetASRResult,
            appBundleID: appBundleID,
            generation: generation,
            operationStartedAt: Date()
        )

        do {
            // Phase 1 — ASR.
            try await ASRPhase(engine: engine, log: log).run(&ctx)
            guard checkpoint(generation) else { return }
            if presetASRResult == nil, let asr = ctx.asrResult {
                undoBookkeeping.setInflightASRResult(asr)
            }

            // Phase 2 — Cleanup.
            hud.show(.thinking, onCancel: makeCancelAction(), onPrimary: makeCancelAction())
            await makeCleanupPhase(bundleID: appBundleID).run(&ctx)
            guard checkpoint(generation) else { return }
            guard let cleanupResult = ctx.cleanupResult, !cleanupResult.cleanedText.isEmpty else {
                log.error("processCapturedAudio: cleaned text was empty")
                undoBookkeeping.clearInflight()
                fail("Transcript was empty")
                return
            }
            lastTranscript = cleanupResult

            // Phase 3 — Paste (also saves transcript + training example).
            state = .pasting
            try await makePastePhase().run(&ctx)
            if let pasteResult = ctx.pasteResult {
                hud.show(pasteResult.didPostPasteEvent ? .pasted : .copied,
                         onPrimary: makeDismissAction())
            }

            // Phase 4 — Learning monitor (fire-and-forget).
            makeLearningPhase().run(ctx)

            try? await Task.sleep(for: .milliseconds(1200))
            guard isCurrentOperation(generation) else { return }
            state = .idle
            undoBookkeeping.clearInflight()
            hud.dismiss()
        } catch {
            guard isCurrentOperation(generation) else { return }
            undoBookkeeping.clearInflight()
            fail(error.localizedDescription)
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
    private func makeCleanupPhase(bundleID: String?) -> CleanupPhase {
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
            log: log
        )
    }

    private func makePastePhase() -> PastePhase {
        PastePhase(
            saveTranscript: { [weak self] id, captured, result, text, bundleID, audioPath in
                guard let self else { throw NSError(domain: "VoiceCoordinator", code: -1) }
                return try self.saveTranscript(
                    transcriptID: id, captured: captured, result: result,
                    cleanedText: text, appBundleID: bundleID, audioPath: audioPath
                )
            },
            persistAudio: { [weak self] captured, id in
                self?.persistAudio(captured: captured, transcriptID: id)
            },
            saveTrainingExample: { [weak self] captured, result, text, id, bundleID, audioPath in
                self?.saveTrainingExample(
                    captured: captured, result: result, cleanedText: text,
                    transcriptID: id, appBundleID: bundleID, audioPath: audioPath
                )
            },
            paste: pasterOverride ?? { text in await CursorPaster.paste(text) },
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
        levelTask?.cancel()
        levelTask = nil
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
        audioPath: String?
    ) throws -> VoiceTranscript {
        try transcripts.save(VoiceTranscriptDraft(
            startedAt: captured.startedAt,
            endedAt: captured.endedAt,
            rawText: result.text,
            cleanedText: cleanedText,
            appBundleID: appBundleID,
            language: result.language,
            modelIdentifier: result.modelIdentifier,
            audioPath: audioPath
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
        let samples = (try? store.listRecentSamples(contextID: ctxID, limit: 10)) ?? []
        return samples.map { ($0.before, $0.after) }
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
    func persistAudio(captured: CapturedAudio, transcriptID: String) -> String? {
        let shouldSave = personalizationSettings().saveTrainingExamplesEnabled
            || historySettings().saveAudio
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
            await stopRecordingAndPaste()
        } else {
            await startRecording()
        }
    }

    private func handleActivationRelease() async {
        guard state == .recording else { return }
        await stopRecordingAndPaste()
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
        levelTask?.cancel()
        levelTask = nil
        _ = audio.stop()
        log.error("Voice failed: \(message, privacy: .public)")
        state = .error(message)
        hud.show(.error(message), onPrimary: makeDismissAction())
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            if case .error = state {
                state = .idle
                hud.dismiss()
            }
        }
    }

    private func isCurrentOperation(_ generation: Int) -> Bool {
        generation == operationGeneration
    }

    private func makeCancelAction() -> () -> Void {
        { [weak self] in Task { @MainActor in self?.cancelCurrentOperation() } }
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
        state = .idle
        hud.dismiss()
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
    case noAudio
    case audioReadFailed
    case audioDecodeFailed
}

extension VoiceCoordinator {
    func retryTranscript(id: String) async throws -> VoiceTranscript {
        let retryStartedAt = Date()
        guard let original = try transcripts.fetch(id: id) else {
            throw VoiceRetryError.transcriptNotFound
        }
        guard let audioPath = original.audioPath else {
            throw VoiceRetryError.noAudio
        }
        guard let trainingExampleStore else {
            throw VoiceRetryError.audioReadFailed
        }

        let wavData: Data
        do {
            wavData = try trainingExampleStore.loadEncryptedAudio(path: audioPath)
        } catch {
            throw VoiceRetryError.audioReadFailed
        }
        let decoded: VoiceAudioCodec.DecodedAudio
        do {
            decoded = try VoiceAudioCodec.decodeWAV(wavData)
        } catch {
            throw VoiceRetryError.audioDecodeFailed
        }

        let asrStartedAt = Date()
        let asrResult = try await engine.transcribe(
            samples: decoded.samples,
            sampleRate: Double(decoded.sampleRate),
            options: .default
        )
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

        let saved = try transcripts.save(
            VoiceTranscriptDraft(
                startedAt: original.startedAt,
                endedAt: original.endedAt,
                rawText: asrResult.text,
                cleanedText: cleanedText,
                appBundleID: original.appBundleID,
                language: asrResult.language,
                modelIdentifier: asrResult.modelIdentifier,
                audioPath: audioPath
            )
        )
        NotificationCenter.default.post(name: .voiceTranscriptAppended, object: saved.id)
        return saved
    }
}
