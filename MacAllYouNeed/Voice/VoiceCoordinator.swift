import AppKit
import Core
import Foundation
import Observation
import OSLog

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

    /// Captured audio for the in-flight transcription. Held while .transcribing
    /// is active so that a mid-stream cancel can offer Undo (re-run the same
    /// audio without making the user re-dictate).
    private var inflightCaptured: CapturedAudio?
    /// ASR result for the in-flight cleanup phase. Set after ASR completes so
    /// that Undo during LLM cleanup can skip ASR and re-run only cleanup.
    private var inflightASRResult: VoiceTranscriptionResult?
    private var inflightAppBundleID: String?

    /// Snapshot kept after cancel so the user can tap Undo to replay it.
    /// Cleared when Undo runs, the HUD is dismissed, or the window expires.
    private var pendingUndo: UndoContext?
    private var undoExpirationTask: Task<Void, Never>?
    private static let undoWindowSeconds: TimeInterval = 5

    private struct UndoContext {
        let captured: CapturedAudio
        let asrResult: VoiceTranscriptionResult?
        let appBundleID: String?
        let cancelledAt: Date
    }

    /// Global Esc-key monitors. Installed on start() so that Esc aborts the
    /// active dictation while another app holds focus (the HUD is a
    /// non-activating panel, so our app rarely gets key events directly).
    /// Requires the Accessibility permission the app already requests for
    /// snippet expansion.
    private var escGlobalMonitor: Any?
    private var escLocalMonitor: Any?

    private(set) var state: State = .idle
    private(set) var lastTranscript: VoiceCleanupResult?

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
        historySettings: @escaping () -> VoiceHistorySettings = { .init() }
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
        activation.onPress = { [weak self] in Task { @MainActor in await self?.handleActivationPress() } }
        activation.onRelease = { [weak self] in Task { @MainActor in await self?.handleActivationRelease() } }
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
        installEscKeyMonitor()
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
        if pendingUndo != nil {
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

    private func processCapturedAudio(
        captured: CapturedAudio,
        presetASRResult: VoiceTranscriptionResult?,
        presetAppBundleID: String?
    ) async {
        operationGeneration += 1
        let generation = operationGeneration
        let operationStartedAt = Date()
        state = .transcribing

        let appBundleID = presetAppBundleID ?? NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        inflightCaptured = captured
        inflightAppBundleID = appBundleID
        inflightASRResult = presetASRResult

        // If we already have an ASR result (undo re-entry), skip straight to the
        // .thinking HUD pill because ASR is already done.
        if presetASRResult == nil {
            hud.show(.transcribing, onCancel: makeCancelAction(), onPrimary: makeCancelAction())
        } else {
            hud.show(.thinking, onCancel: makeCancelAction(), onPrimary: makeCancelAction())
        }
        do {
            log.info("ASR start — app: \(appBundleID ?? "nil", privacy: .public) presetASR: \(presetASRResult != nil, privacy: .public)")

            // Load personalization context for this app (style hints only).
            let (appCtx, globalCtx) = loadContexts(bundleID: appBundleID)
            let recentExamplesContext = (appCtx?.enabled == false)
                ? nil
                : (appCtx ?? globalCtx)

            let result: VoiceTranscriptionResult
            var asrMs: Int?
            if let preset = presetASRResult {
                result = preset
            } else {
                let asrStart = Date()
                result = try await engine.transcribe(
                    samples: captured.samples,
                    sampleRate: captured.sampleRate,
                    options: .default
                )
                asrMs = Int(Date().timeIntervalSince(asrStart) * 1000)
                log.info("ASR done — \(asrMs ?? 0, privacy: .public)ms model: \(result.modelIdentifier, privacy: .public) lang: \(result.language.rawValue, privacy: .public) chars: \(result.text.count, privacy: .public)")
                guard isCurrentOperation(generation), state == .transcribing else {
                    clearInflightContext()
                    return
                }
                // Capture result so a cancel during cleanup can replay only the cleanup pass.
                inflightASRResult = result
            }
            let dictionaryEntries = (try? dictionary?.list()) ?? []

            // Build personalization-enriched cleanup request via the testable builder.
            let recentExamples = loadRecentExamples(context: recentExamplesContext)
            let cleanupRequest = Self.buildCleanupRequest(
                rawText: result.text,
                appBundleID: appBundleID,
                language: result.language,
                dictionaryEntries: dictionaryEntries,
                appContext: appCtx,
                globalContext: globalCtx,
                recentExamples: recentExamples
            )

            hud.show(.thinking, onCancel: makeCancelAction(), onPrimary: makeCancelAction())
            let cleanup = makeCleanupPipeline(
                elapsedBeforeCleanupSeconds: Date().timeIntervalSince(operationStartedAt)
            )
            log.info("LLM cleanup start — text length: \(result.text.count, privacy: .public) chars")
            let cleanupStart = Date()
            let rawCleanupResult = await cleanup.clean(cleanupRequest)
            let cleanupMs = Int(Date().timeIntervalSince(cleanupStart) * 1000)
            let totalMs = Int(Date().timeIntervalSince(operationStartedAt) * 1000)
            let cleanupResult = rawCleanupResult.withTimings(
                asrMs: asrMs,
                cleanupMs: cleanupMs,
                totalMs: totalMs
            )
            log.info("LLM cleanup done — \(cleanupMs, privacy: .public)ms total: \(totalMs, privacy: .public)ms usedLLM: \(cleanupResult.usedLLM, privacy: .public) provider: \(cleanupResult.providerIdentifier ?? "none", privacy: .public) chars: \(cleanupResult.cleanedText.count, privacy: .public) fallback: \(cleanupResult.fallbackReason?.rawValue ?? "none", privacy: .public)")
            guard isCurrentOperation(generation), state == .transcribing else {
                clearInflightContext()
                return
            }
            let text = cleanupResult.cleanedText
            guard !text.isEmpty else {
                log.error("processCapturedAudio: cleaned text was empty")
                clearInflightContext()
                fail("Transcript was empty")
                return
            }
            lastTranscript = cleanupResult

            // Snapshot AX target before paste so the monitor can track the field.
            let axSnapshot = AXFocusedTextReader.snapshotFocused()

            state = .pasting
            let pasteResult = await CursorPaster.paste(text)
            log.info("paste — didPost: \(pasteResult.didPostPasteEvent, privacy: .public) chars: \(text.count, privacy: .public)")
            let transcriptID = UUID().uuidString
            let audioPath = persistAudio(captured: captured, transcriptID: transcriptID)
            let savedTranscript = try saveTranscript(
                transcriptID: transcriptID,
                captured: captured,
                result: result,
                cleanedText: text,
                appBundleID: appBundleID,
                audioPath: audioPath
            )
            log.info("transcript saved — id: \(savedTranscript.id, privacy: .public) audioPath: \(audioPath ?? "nil", privacy: .public)")
            saveTrainingExample(
                captured: captured,
                result: result,
                cleanedText: text,
                transcriptID: savedTranscript.id,
                appBundleID: appBundleID,
                audioPath: audioPath
            )
            NotificationCenter.default.post(name: .voiceTranscriptAppended, object: savedTranscript.id)

            hud.show(
                pasteResult.didPostPasteEvent ? .pasted : .copied,
                onPrimary: makeDismissAction()
            )

            // Fire post-edit learning monitor (fire-and-forget).
            startLearningMonitor(
                pastedText: text,
                transcriptID: savedTranscript.id,
                appBundleID: appBundleID,
                isAutoSubmit: false,
                snapshot: axSnapshot
            )

            try? await Task.sleep(for: .milliseconds(1200))
            guard isCurrentOperation(generation) else { return }
            state = .idle
            clearInflightContext()
            hud.dismiss()
        } catch {
            guard isCurrentOperation(generation) else { return }
            clearInflightContext()
            fail(error.localizedDescription)
        }
    }

    /// Re-runs the transcribe + cleanup + paste flow against the audio that was
    /// in flight when the user last cancelled. If the cancel happened after
    /// ASR completed, this skips ASR and replays just the cleanup pass.
    func undoLastCancel() async {
        guard let undo = pendingUndo else { return }
        pendingUndo = nil
        cancelUndoExpiration()
        log.info("undoLastCancel — replay (asrPreset: \(undo.asrResult != nil, privacy: .public) age: \(Int(Date().timeIntervalSince(undo.cancelledAt) * 1000), privacy: .public)ms)")
        await processCapturedAudio(
            captured: undo.captured,
            presetASRResult: undo.asrResult,
            presetAppBundleID: undo.appBundleID
        )
    }

    private func clearInflightContext() {
        inflightCaptured = nil
        inflightASRResult = nil
        inflightAppBundleID = nil
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
        guard pendingUndo != nil else { return }
        log.info("undo window expired — dismissing cancelled pill")
        pendingUndo = nil
        cancelUndoExpiration()
        hud.dismiss()
    }

    func cancelCurrentOperation() {
        guard state == .recording || state == .transcribing else { return }
        let wasRecording = state == .recording
        let savedTranscribingCaptured = inflightCaptured
        let savedASRResult = inflightASRResult
        let savedAppBundleID = inflightAppBundleID

        operationGeneration += 1
        levelTask?.cancel()
        levelTask = nil
        monitorTask?.cancel()
        monitorTask = nil
        // During .recording the mic is still open; stop() returns the audio we
        // captured so far so a recording-time cancel can also offer Undo.
        // During .transcribing the mic was already stopped — stop() returns nil
        // and we fall back to inflightCaptured (set inside processCapturedAudio).
        let stoppedAudio = audio.stop()
        state = .idle
        clearInflightContext()

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
            pendingUndo = UndoContext(
                captured: captured,
                asrResult: undoASRResult,
                appBundleID: undoAppBundleID,
                cancelledAt: Date()
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

    private func installEscKeyMonitor() {
        if escGlobalMonitor != nil || escLocalMonitor != nil { return }
        let handler: @Sendable (NSEvent) -> Void = { [weak self] event in
            let keyCode = event.keyCode
            // Esc, Return, or numpad Enter — every other key is ignored.
            guard keyCode == 0x35 || keyCode == 0x24 || keyCode == 0x4C else { return }
            Task { @MainActor in
                guard let self else { return }
                switch keyCode {
                case 0x35: self.handleEscKey()
                case 0x24, 0x4C: self.handleEnterKey()
                default: break
                }
            }
        }
        // Global: events while another app has focus (the common case — the HUD
        // is a non-activating panel so our app rarely is the active app).
        escGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            handler(event)
        }
        // Local: events while our app does happen to be active. Return the
        // event so other handlers still see it — we react, we don't swallow.
        escLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handler(event)
            return event
        }
    }

    private func handleEscKey() {
        if state == .recording || state == .transcribing {
            log.info("esc — cancelling current operation (state: \(String(describing: self.state), privacy: .public))")
            cancelCurrentOperation()
        } else if pendingUndo != nil {
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
        guard pendingUndo != nil else { return }
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
