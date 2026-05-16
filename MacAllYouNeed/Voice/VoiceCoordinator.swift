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

    private(set) var state: State = .idle
    private(set) var lastTranscript: VoiceCleanupResult?

    init(
        transcripts: VoiceTranscriptStore,
        dictionary: VoiceDictionaryStore? = nil,
        personalizationStore: VoicePersonalizationStore? = nil,
        trainingExampleStore: VoiceTrainingExampleStore? = nil,
        personalizationSettings: @escaping () -> VoicePersonalizationSettings = { .default },
        engine: any VoiceTranscriptionEngine = Qwen3Engine(),
        cleanupSettings: VoiceCleanupSettings = VoiceCleanupSettingsStore.load(),
        cleanupKeyStore: VoiceCleanupKeyStore = VoiceCleanupKeyStore(keychain: SystemKeychain()),
        learningMonitor: VoicePostEditLearningMonitor? = nil,
        summarizer: VoicePersonalizationSummarizer? = nil
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
            engine = Qwen3Engine()
        case .groq:
            let keyStore = GroqASRKeyStore(keychain: keychain)
            engine = GroqASREngine(
                settings: { GroqASRSettingsStore.load() },
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

        guard state == .idle else { return }
        lastTranscript = nil
        guard await audio.requestPermission() else {
            fail("Microphone permission denied")
            return
        }
        do {
            try audio.start()
            operationGeneration += 1
            state = .recording
            hud.show(.recording(level: 0), onCancel: makeCancelAction(), onPrimary: makeStopAction())
            startLevelUpdates()
        } catch {
            fail(error.localizedDescription)
        }
    }

    func stopRecordingAndPaste() async {
        guard state == .recording else { return }
        let generation = operationGeneration
        levelTask?.cancel()
        levelTask = nil

        guard let captured = audio.stop(), captured.samples.count > 800 else {
            fail("No usable audio captured")
            return
        }

        state = .transcribing
        hud.show(.transcribing, onCancel: makeCancelAction())
        do {
            let appBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

            // Load personalization context for this app (style hints only).
            let (appCtx, globalCtx) = loadContexts(bundleID: appBundleID)
            let recentExamplesContext = (appCtx?.enabled == false)
                ? nil
                : (appCtx ?? globalCtx)

            let result = try await engine.transcribe(
                samples: captured.samples,
                sampleRate: captured.sampleRate,
                options: .default
            )
            guard isCurrentOperation(generation), state == .transcribing else { return }
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

            let cleanup = makeCleanupPipeline()
            let cleanupResult = await cleanup.clean(cleanupRequest)
            guard isCurrentOperation(generation), state == .transcribing else { return }
            let text = cleanupResult.cleanedText
            guard !text.isEmpty else {
                fail("Transcript was empty")
                return
            }
            lastTranscript = cleanupResult

            // Snapshot AX target before paste so the monitor can track the field.
            let axSnapshot = AXFocusedTextReader.snapshotFocused()

            state = .pasting
            let pasteResult = await CursorPaster.paste(text)
            let savedTranscript = try saveTranscript(
                captured: captured, result: result, cleanedText: text, appBundleID: appBundleID
            )
            saveTrainingExample(
                captured: captured,
                result: result,
                cleanedText: text,
                transcriptID: savedTranscript.id,
                appBundleID: appBundleID
            )

            hud.show(
                pasteResult.didPostPasteEvent ? .pasted : .error("Text copied. Press Command-V to paste."),
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

            try? await Task.sleep(for: .seconds(1))
            guard isCurrentOperation(generation) else { return }
            state = .idle
            hud.dismiss()
        } catch {
            guard isCurrentOperation(generation) else { return }
            fail(error.localizedDescription)
        }
    }

    func cancelCurrentOperation() {
        guard state == .recording || state == .transcribing else { return }
        operationGeneration += 1
        levelTask?.cancel()
        levelTask = nil
        monitorTask?.cancel()
        monitorTask = nil
        _ = audio.stop()
        state = .idle
        hud.dismiss()
    }

    private func saveTranscript(
        captured: CapturedAudio,
        result: VoiceTranscriptionResult,
        cleanedText: String,
        appBundleID: String?
    ) throws -> VoiceTranscript {
        try transcripts.save(VoiceTranscriptDraft(
            startedAt: captured.startedAt,
            endedAt: captured.endedAt,
            rawText: result.text,
            cleanedText: cleanedText,
            appBundleID: appBundleID,
            language: result.language,
            modelIdentifier: result.modelIdentifier,
            audioPath: nil
        ))
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

    private func saveTrainingExample(
        captured: CapturedAudio,
        result: VoiceTranscriptionResult,
        cleanedText: String,
        transcriptID: String,
        appBundleID: String?
    ) {
        guard personalizationSettings().saveTrainingExamplesEnabled,
              let trainingExampleStore else { return }

        let sampleRate = max(1, Int(captured.sampleRate.rounded()))
        let wavData = GroqASREngine.encodeWAV(samples: captured.samples, sampleRate: sampleRate)
        let audioPath: String?
        do {
            audioPath = try trainingExampleStore.saveEncryptedAudio(wavData, id: transcriptID)
        } catch {
            audioPath = nil
            log.error("Voice training audio save failed: \(error.localizedDescription, privacy: .public)")
        }

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

    private static func trimmedOrNil(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func makeCleanupPipeline() -> VoiceCleanupPipeline {
        do {
            let provider = try VoiceCleanupProviderFactory.makeProvider(
                settings: cleanupSettings,
                keyStore: cleanupKeyStore
            )
            return VoiceCleanupPipeline(
                provider: provider,
                timeout: .seconds(Int64(cleanupSettings.normalizedTimeoutSeconds))
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
                hud.show(.recording(level: audio.peakLevel), onCancel: makeCancelAction(), onPrimary: makeStopAction())
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

    private func makeStopAction() -> () -> Void {
        { [weak self] in Task { @MainActor in await self?.stopRecordingAndPaste() } }
    }

    private func makeDismissAction() -> () -> Void {
        { [weak self] in
            Task { @MainActor in
                self?.operationGeneration += 1
                self?.state = .idle
                self?.hud.dismiss()
            }
        }
    }
}

enum VoiceLevelSampling {
    static let intervalMilliseconds = 25
}
