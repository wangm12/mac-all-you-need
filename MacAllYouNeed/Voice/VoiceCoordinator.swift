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
    private let engine: any VoiceTranscriptionEngine
    private let transcripts: VoiceTranscriptStore
    private let dictionary: VoiceDictionaryStore?
    private let personalizationStore: VoicePersonalizationStore?
    private let personalizationSettings: () -> VoicePersonalizationSettings
    private let cleanupKeyStore: VoiceCleanupKeyStore
    private let autoSubmit: VoiceAutoSubmitService
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
        personalizationSettings: @escaping () -> VoicePersonalizationSettings = { .default },
        engine: any VoiceTranscriptionEngine = Qwen3Engine(),
        cleanupSettings: VoiceCleanupSettings = VoiceCleanupSettingsStore.load(),
        cleanupKeyStore: VoiceCleanupKeyStore = VoiceCleanupKeyStore(keychain: SystemKeychain()),
        autoSubmit: VoiceAutoSubmitService = VoiceAutoSubmitService(),
        learningMonitor: VoicePostEditLearningMonitor? = nil,
        summarizer: VoicePersonalizationSummarizer? = nil
    ) {
        self.transcripts = transcripts
        self.dictionary = dictionary
        self.personalizationStore = personalizationStore
        self.personalizationSettings = personalizationSettings
        self.engine = engine
        self.cleanupSettings = cleanupSettings
        self.cleanupKeyStore = cleanupKeyStore
        self.autoSubmit = autoSubmit
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

            // Load personalization context for this app (overrides + style hints).
            let (appCtx, globalCtx) = loadContexts(bundleID: appBundleID)
            let effectiveCtx = appCtx ?? globalCtx

            let result = try await engine.transcribe(
                samples: captured.samples,
                sampleRate: captured.sampleRate,
                options: VoiceTranscriptionOptions(
                    preferredModelIdentifier: effectiveCtx?.asrModelID
                )
            )
            guard isCurrentOperation(generation), state == .transcribing else { return }
            let dictionaryEntries = (try? dictionary?.list()) ?? []

            // Build personalization-enriched cleanup request.
            let recentExamples = loadRecentExamples(context: effectiveCtx)
            let cleanupRequest = VoiceCleanupRequest(
                rawText: result.text,
                appBundleID: appBundleID,
                language: result.language,
                dictionaryEntries: dictionaryEntries,
                appInstructions: effectiveCtx?.customPromptOverride.flatMap {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0
                },
                personalStyleNotes: globalCtx?.styleNotes.flatMap {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0
                },
                personalizationSummary: (appCtx?.summary ?? globalCtx?.summary).flatMap {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0
                },
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

            hud.show(
                pasteResult.didPostPasteEvent ? .pasted : .error("Text copied. Press Command-V to paste."),
                onPrimary: makeDismissAction()
            )

            // Auto-submit (app-specific).
            let autoSubmitKey = effectiveCtx?.autoSubmitKey
            if pasteResult.didPostPasteEvent, let key = autoSubmitKey, key != .none {
                try? await Task.sleep(for: .milliseconds(80))
                autoSubmit.submit(key)
            }

            // Fire post-edit learning monitor (fire-and-forget).
            let isAutoSubmit = autoSubmitKey != nil && autoSubmitKey != .none
            startLearningMonitor(
                pastedText: text,
                transcriptID: savedTranscript.id,
                appBundleID: appBundleID,
                isAutoSubmit: isAutoSubmit,
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
        let app = (try? personalizationStore?.fetchContext(bundleID: bundleID)).flatMap {
            $0.enabled ? $0 : nil
        }
        return (app, global)
    }

    private func loadRecentExamples(context: VoicePersonalizationContext?) -> [(before: String, after: String)] {
        guard let ctxID = context?.id, let store = personalizationStore else { return [] }
        let samples = (try? store.listRecentSamples(contextID: ctxID, limit: 10)) ?? []
        return samples.map { ($0.before, $0.after) }
    }

    // Internal for testing via VoiceCoordinatorPersonalizationTests.
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

        // I3: if an app context exists and the user has disabled it, respect that.
        // Do NOT fall through to global when the user explicitly opted this app out.
        if let bundleID = appBundleID,
           let existing = try? store.fetchContext(bundleID: bundleID),
           !existing.enabled
        {
            return
        }

        // C2: ensure a context row exists for this app. Create on first use.
        let ctxID: String
        if let bundleID = appBundleID {
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
                    .init(bundleID: VoicePersonalizationContext.globalBundleID,
                          displayName: VoicePersonalizationContext.globalDisplayName)
                ) else { return }
                ctxID = created.id
            }
        }

        let maxSamples = personalizationSettings().rollingCacheMaxSamples

        monitorTask = Task { [weak self] in
            guard let self else { return }
            let draft = await self.learningMonitor.observe(
                pastedText: pastedText,
                transcriptID: transcriptID,
                contextID: ctxID,
                isAutoSubmitContext: isAutoSubmit,
                snapshot: snapshot
            )
            guard let draft else { return }
            try? store.appendSample(draft)
            // I4: enforce retention limits on every append so they hold even when
            // the LLM provider is unavailable and the summarizer never fires.
            try? store.expireSamplesByCount(contextID: ctxID, max: maxSamples)
            try? store.expireSamplesByDate()
            await self.summarizer?.maybeRun(contextID: ctxID)
        }
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
                try? await Task.sleep(for: .milliseconds(100))
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
