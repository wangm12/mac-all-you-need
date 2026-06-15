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
    /// The currently selected ASR engine. All transcription is dispatched
    /// through this property; engine selection happens in `applyASRProvider`.
    var activeEngine: (any ASRProviding)?
    private let activation = VoiceActivationMonitor()
    let log = Logger(subsystem: "com.macallyouneed.voice", category: "coordinator")

    private var activationMonitoringSuspended = false
    // These are internal (not private) so VoicePipelineDelegate conformance can expose them.
    var inputSourceChangedDuringRun = false
    var inputSourceAtRecordingStart: String?
    private var inputSourceObserver: NSObjectProtocol?
    var isStoppingRecording = false
    var operationGeneration = 0

    // MARK: - Sub-controllers

    /// Owns the MiniVoiceHUD panel, EscKeyMonitor, and level sampling.
    let hudPresenter: VoiceHUDPresenter
    /// Owns the ASR pipeline, live-ASR session, undo replay, and persistence.
    let pipeline: VoicePipelineController

    // MARK: - Pipeline metrics (bridged through VoicePipelineDelegate)

    var pendingPipelineMetrics: VoicePipelineController.PipelineMetrics?

    // MARK: - Observable state
    // `state` and `lastTranscript` are effectively read-only to external callers
    // (no external code sets them), but they must be `internal` (not private(set))
    // so VoicePipelineDelegate conformance can expose a settable interface to
    // VoicePipelineController, which is a separate type in the same module.
    var state: State = .idle
    var lastTranscript: VoiceCleanupResult?

    // MARK: - Undo bookkeeping (forwarded to pipeline)

    /// Exposed (internal) for tests — identical surface to before.
    var undoBookkeeping: UndoContextBookkeeping { pipeline.undoBookkeeping }

    // MARK: - Reminder integration

    var activeIntent: VoiceIntent = .dictation
    var reminderWriterOverride: (any RemindersWriter)?
    var remindersWorker: RemindersFeatureWorker?
    let reminderSettings: () -> ReminderSettings
    var lastCreatedReminder: CreatedReminder?

    // MARK: - Init (convenience — production callers)

    convenience init(
        transcripts: VoiceTranscriptStore,
        dictionary: VoiceDictionaryStore? = nil,
        personalizationStore: VoicePersonalizationStore? = nil,
        trainingExampleStore: VoiceTrainingExampleStore? = nil,
        personalizationSettings: @escaping () -> VoicePersonalizationSettings = { .default },
        engine: (any ASRProviding)? = VoiceLocalASREngine(),
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
        engine: (any ASRProviding)? = VoiceLocalASREngine(),
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
        self.activeEngine = engine
        self.reminderSettings = reminderSettings

        let log = Logger(subsystem: "com.macallyouneed.voice", category: "coordinator")

        let hud = VoiceHUDPresenter(log: log)
        hudPresenter = hud

        let pipe = VoicePipelineController(
            transcripts: transcripts,
            dictionary: dictionary,
            personalizationStore: personalizationStore,
            trainingExampleStore: trainingExampleStore,
            personalizationSettings: personalizationSettings,
            cleanupKeyStore: cleanupKeyStore,
            learningMonitor: learningMonitor,
            summarizer: summarizer,
            historySettings: historySettings,
            cleanupPipelineFactory: cleanupPipelineFactory,
            paster: paster,
            snapshotFocused: snapshotFocused,
            learningStarter: learningStarter,
            cleanupObserver: cleanupObserver,
            log: log
        )
        pipeline = pipe

        // Wire collaborators.
        pipe.hudPresenter = hud
        pipe.delegate = self

        activation.onPress = { [weak self] in Task { @MainActor in await self?.handleActivationPress() } }
        activation.onRelease = { [weak self] in Task { @MainActor in await self?.handleActivationRelease() } }

        // Wire HUD presenter callbacks back to coordinator actions.
        hud.onCancel = { [weak self] in Task { @MainActor in self?.cancelCurrentOperation() } }
        hud.onDismissUndo = { [weak self] in Task { @MainActor in self?.expirePendingUndo() } }
        hud.onUndo = { [weak self] in await self?.undoLastCancel() }
        hud.hasPendingUndo = { [weak self] in self?.pipeline.undoBookkeeping.hasPendingUndo ?? false }
        hud.isStoppable = { [weak self] in
            guard let self else { return false }
            return state == .recording || state == .transcribing
        }
    }

    // MARK: - Public interface (unchanged)

    func start() {
        guard !activationMonitoringSuspended else { return }
        do {
            try activation.start(settings: VoiceActivationSettingsStore.load())
        } catch {
            log.error("Voice activation failed: \(error.localizedDescription, privacy: .public)")
        }
        if let local = activeEngine as? VoiceLocalASREngine {
            Task.detached { await local.warmup() }
        } else if let qwen = activeEngine as? Qwen3Engine {
            Task.detached { await qwen.warmup() }
        }
        hudPresenter.installEscMonitor()
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
        // cleanupSettings is no longer stored here; kept as no-op for
        // API compatibility — callers may still call it after Settings changes.
        // VoicePipelineController reads VoiceCleanupSettingsStore.load() at
        // cleanup time so it always uses the current persisted settings.
        _ = settings
    }

    /// Hot-swaps the ASR engine so provider changes in Settings take effect
    /// on the next dictation without requiring an app restart.
    func applyASRProvider(_ providerKind: VoiceASRProviderKind, keychain: KeychainBackend) {
        switch providerKind {
        case .local:
            let local = VoiceLocalASREngine()
            activeEngine = local
            Task.detached { await local.warmup() }
        case .groq:
            let keyStore = GroqASRKeyStore(keychain: keychain)
            activeEngine = GroqASREngine(
                settings: { GroqASRSettingsStore.load() },
                keyStore: keyStore
            )
        case .elevenLabs, .openAITranscribe, .deepgram:
            let keyStore = VoiceCloudASRKeyStore(keychain: keychain)
            activeEngine = VoiceCloudASREngine(
                providerKind: providerKind,
                settings: { VoiceCloudASRSettingsStore.load() },
                keyStore: keyStore
            )
        case .openAIRealtime:
            let keyStore = VoiceCloudASRKeyStore(keychain: keychain)
            activeEngine = OpenAIRealtimeASREngine(
                keyStore: keyStore,
                settings: { VoiceCloudASRSettingsStore.load() }
            )
        }
    }

    func stop() {
        operationGeneration += 1
        hudPresenter.cancelErrorDismissTask()
        activationMonitoringSuspended = false
        activation.stop()
        hudPresenter.stopLevelUpdates()
        pipeline.stopLiveFeedTask()
        Task { await self.pipeline.cancelLiveASR() }
        pipeline.stopLearningMonitorTask()
        _ = audio.stop()
        uninstallInputSourceObserver()
        hudPresenter.dismiss()
    }

    func startRecording() async {
        pipeline.stopLearningMonitorTask()
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
        hudPresenter.showRecording(level: 0)

        // ── Decision tree: resolve which engine to use ──────────────────────
        let settings = VoiceASRSettingsStore.load()
        let localModelInstalled = VoiceModelManager.isLocalASRModelInstalled(settings.modelID)
        // Derive local capabilities from the model ID without allocating an engine actor.
        let localCaps: VoiceASRCapabilities = settings.modelID.runtime == .qwenCoreML
            ? VoiceASRCapabilities(supportsStreaming: true, requiresNetwork: false, emitsPartials: false)
            : .batchOnly
        let cloudKeyPresent: Bool
        if settings.providerKind != .local {
            let keyStore = VoiceCloudASRKeyStore(keychain: SystemKeychain())
            cloudKeyPresent = (try? keyStore.apiKey(for: settings.providerKind)) != nil
        } else {
            cloudKeyPresent = false
        }
        let decision = VoiceRecordingStartPlanner.resolve(
            configured: settings.providerKind,
            cloudKeyPresent: cloudKeyPresent,
            isOnline: NetworkReachability.shared.isOnline,
            localModelInstalled: localModelInstalled,
            localEngineCapabilities: localCaps
        )
        switch decision {
        case .blocked(let reason):
            log.error("startRecording blocked: \(reason.userMessage, privacy: .public)")
            fail(reason.userMessage)
            return
        case .start(let provider, _):
            // If the planner chose local but we're configured for cloud, hot-swap the engine.
            // applyASRProvider already fires Task.detached warmup, so skip the guarded warmup
            // below to avoid two concurrent warmup calls on the same actor.
            if provider == .local, settings.providerKind != .local {
                log.info("startRecording: falling back to local engine (cloud unavailable)")
                applyASRProvider(.local, keychain: SystemKeychain())
                // Warmup fired by applyASRProvider — skip the guard below.
                break
            }
        }
        // ────────────────────────────────────────────────────────────────────

        // Await warmup before starting audio so the model is ready for the first
        // ASR call. On first dictation this prevents silent ASR failures from an
        // unloaded model. Subsequent calls return quickly (model already warm).
        // Cap at 3s so a corrupt model file or disk stall cannot hang forever.
        // (Skipped when hot-swap already fired warmup above.)
        if let local = activeEngine as? VoiceLocalASREngine {
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await local.warmup() }
                group.addTask { try? await Task.sleep(for: .seconds(3)) }
                await group.next()
                group.cancelAll()
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
            hudPresenter.startLevelUpdates(peakLevelProvider: { [weak self] in self?.audio.peakLevel ?? 0 })
            let gen = operationGeneration
            await pipeline.beginLiveASR(generation: operationGeneration, audioSnapshotProvider: { [weak self] in
                self?.audio.liveFeedSnapshot()
            }, onPartial: { [weak self] partial in
                guard let self, self.operationGeneration == gen, self.state == .recording else { return }
                self.hudPresenter.showLivePartial(partial.text)
            })
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
        hudPresenter.stopLevelUpdates()
        pipeline.stopLiveFeedTask()

        let liveGeneration = pipeline.currentLiveSessionGeneration
        if let snapshot = audio.liveFeedSnapshot(),
           liveGeneration == pipeline.currentLiveSessionGeneration
        {
            try? await pipeline.drainLiveFeed(snapshot: snapshot)
        }

        guard let captured = audio.stop(), captured.samples.count > 800 else {
            await pipeline.cancelLiveASR()
            log.error("stopRecordingAndPaste: insufficient audio captured (need >800 samples)")
            fail("No usable audio captured")
            return
        }

        let liveFinishStartedAt = Date()
        let presetASRResult = (await pipeline.withTimeout(seconds: 0.8) {
            await self.pipeline.finishLiveASRIfEligible(
                captured: captured,
                generation: liveGeneration
            )
        }) ?? nil
        if presetASRResult == nil {
            log.info("live ASR finalize timed out or empty — continuing with batch ASR")
        }
        pendingPipelineMetrics = VoicePipelineController.PipelineMetrics(
            recordingMs: Int(captured.endedAt.timeIntervalSince(captured.startedAt) * 1000),
            liveFinishMs: Int(Date().timeIntervalSince(liveFinishStartedAt) * 1000),
            liveUsed: presetASRResult != nil
        )

        log.info("stopRecordingAndPaste — samples: \(captured.samples.count, privacy: .public) sampleRate: \(captured.sampleRate, privacy: .public) peak: \(captured.peakLevel, privacy: .public) liveASR: \(presetASRResult != nil, privacy: .public)")
        await pipeline.processCapturedAudio(
            captured: captured,
            presetASRResult: presetASRResult,
            presetAppBundleID: nil
        )
    }

    /// Exposed for tests (spine tests call this directly on VoiceCoordinator).
    func processCapturedAudio(
        captured: CapturedAudio,
        presetASRResult: VoiceTranscriptionResult?,
        presetAppBundleID: String?,
        retrySourceTranscriptID: String? = nil
    ) async {
        await pipeline.processCapturedAudio(
            captured: captured,
            presetASRResult: presetASRResult,
            presetAppBundleID: presetAppBundleID,
            retrySourceTranscriptID: retrySourceTranscriptID
        )
    }

    func cancelCurrentOperation() {
        guard state == .recording || state == .transcribing else { return }
        let wasRecording = state == .recording
        let savedTranscribingCaptured = undoBookkeeping.inflightCaptured
        let savedASRResult = undoBookkeeping.inflightASRResult
        let savedAppBundleID = undoBookkeeping.inflightAppBundleID

        operationGeneration += 1
        activeIntent = .dictation
        hudPresenter.stopLevelUpdates()
        pipeline.stopLiveFeedTask()
        Task { await self.pipeline.cancelLiveASR() }
        pipeline.stopLearningMonitorTask()
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
            hudPresenter.showCancelled()
            pipeline.scheduleUndoExpiration()
        } else {
            log.info("cancelCurrentOperation — no usable audio, dismissing without undo")
            hudPresenter.dismiss()
        }
    }

    func undoLastCancel() async {
        await pipeline.undoLastCancel()
    }

    func isCurrentOperation(_ generation: Int) -> Bool {
        pipeline.isCurrentOperation(generation)
    }

    /// Plan 03 — terminal teardown shared by the reminder path.
    func teardownAfterReminderRun() {
        state = .idle
        undoBookkeeping.clearInflight()
        hudPresenter.dismiss()
        activeIntent = .dictation
    }

    // MARK: - Personalization / learning (forwarded)

    func startLearningMonitor(
        pastedText: String,
        transcriptID: String?,
        appBundleID: String?,
        isAutoSubmit: Bool,
        snapshot: AXTargetSnapshot?
    ) {
        pipeline.startLearningMonitor(
            pastedText: pastedText,
            transcriptID: transcriptID,
            appBundleID: appBundleID,
            isAutoSubmit: isAutoSubmit,
            snapshot: snapshot
        )
    }

    /// Internal+static for VoiceCoordinatorPersonalizationTests.
    static func buildCleanupRequest(
        rawText: String,
        appBundleID: String?,
        language: VoiceLanguage,
        dictionaryEntries: [VoiceDictionaryEntry],
        appContext: VoicePersonalizationContext?,
        globalContext: VoicePersonalizationContext?,
        recentExamples: [(before: String, after: String)]
    ) -> VoiceCleanupRequest {
        VoicePipelineController.buildCleanupRequest(
            rawText: rawText,
            appBundleID: appBundleID,
            language: language,
            dictionaryEntries: dictionaryEntries,
            appContext: appContext,
            globalContext: globalContext,
            recentExamples: recentExamples
        )
    }

    /// Internal for testing (VoiceCoordinatorPersonalizationTests).
    @discardableResult
    func persistAudio(captured: CapturedAudio, transcriptID: String, forceSave: Bool = false) -> String? {
        pipeline.persistAudio(captured: captured, transcriptID: transcriptID, forceSave: forceSave)
    }

    // MARK: - Private helpers

    private func expirePendingUndo() {
        pipeline.expirePendingUndo()
    }

    private func fail(_ message: String) {
        hudPresenter.stopLevelUpdates()
        _ = audio.stop()
        log.error("Voice failed: \(message, privacy: .public)")
        state = .error(message)
        hudPresenter.showFailure(message) { [weak self] in
            self?.state = .idle
        }
    }

    private func showTranscribingPhase(_ phase: MiniVoiceHUD.TranscribingSubphase) {
        log.info("voice.stage — \(String(describing: phase), privacy: .public)")
        hudPresenter.showTranscribingPhase(phase)
    }

    private func handleActivationPress() async {
        if state == .recording {
            showTranscribingPhase(.finalizing)
            await stopRecordingAndPaste()
        } else if case .error = state {
            hudPresenter.cancelErrorDismissTask()
            state = .idle
            hudPresenter.dismiss()
            activeIntent = .dictation
            await startRecording()
        } else if state == .transcribing || state == .pasting {
            return
        } else {
            activeIntent = .dictation
            await startRecording()
        }
    }

    private func handleActivationRelease() async {
        guard state == .recording else { return }
        await stopRecordingAndPaste()
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
}

// MARK: - VoicePipelineDelegate conformance

extension VoiceCoordinator: VoicePipelineDelegate {}

// MARK: - Retry

extension VoiceCoordinator {
    func retryTranscript(id: String) async throws -> VoiceTranscript {
        try await pipeline.retryTranscript(id: id)
    }
}

// MARK: - Supporting types

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
