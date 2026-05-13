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
    private let appProfiles: VoiceAppProfileStore?
    private let cleanupKeyStore: VoiceCleanupKeyStore
    private let autoSubmit: VoiceAutoSubmitService
    private let hud = MiniVoiceHUD()
    private let activation = VoiceActivationMonitor()
    private let log = Logger(subsystem: "com.macallyouneed.voice", category: "coordinator")
    private var levelTask: Task<Void, Never>?
    private var cleanupSettings: VoiceCleanupSettings
    private var operationGeneration = 0
    private var activationMonitoringSuspended = false

    private(set) var state: State = .idle
    private(set) var lastTranscript: VoiceCleanupResult?

    init(
        transcripts: VoiceTranscriptStore,
        dictionary: VoiceDictionaryStore? = nil,
        appProfiles: VoiceAppProfileStore? = nil,
        engine: any VoiceTranscriptionEngine = Qwen3Engine(),
        cleanupSettings: VoiceCleanupSettings = VoiceCleanupSettingsStore.load(),
        cleanupKeyStore: VoiceCleanupKeyStore = VoiceCleanupKeyStore(keychain: SystemKeychain()),
        autoSubmit: VoiceAutoSubmitService = VoiceAutoSubmitService()
    ) {
        self.transcripts = transcripts
        self.dictionary = dictionary
        self.appProfiles = appProfiles
        self.engine = engine
        self.cleanupSettings = cleanupSettings
        self.cleanupKeyStore = cleanupKeyStore
        self.autoSubmit = autoSubmit
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
        _ = audio.stop()
        hud.dismiss()
    }

    func startRecording() async {
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
            let result = try await engine.transcribe(samples: captured.samples, sampleRate: captured.sampleRate)
            guard isCurrentOperation(generation), state == .transcribing else { return }
            let appBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            let dictionaryEntries = (try? dictionary?.list()) ?? []
            let appProfile = activeProfile(for: appBundleID)
            let cleanup = makeCleanupPipeline()
            let cleanupResult = await cleanup.clean(VoiceCleanupRequest(
                rawText: result.text,
                appBundleID: appBundleID,
                language: result.language,
                dictionaryEntries: dictionaryEntries,
                appInstructions: appProfile?.config.customPrompt
            ))
            guard isCurrentOperation(generation), state == .transcribing else { return }
            let text = cleanupResult.cleanedText
            guard !text.isEmpty else {
                fail("Transcript was empty")
                return
            }
            lastTranscript = cleanupResult

            state = .pasting
            let pasteResult = await CursorPaster.paste(text)
            _ = try saveTranscript(captured: captured, result: result, cleanedText: text, appBundleID: appBundleID)

            hud.show(
                pasteResult.didPostPasteEvent ? .pasted : .error("Text copied. Press Command-V to paste."),
                onPrimary: makeDismissAction()
            )
            if pasteResult.didPostPasteEvent, let autoSubmitKey = appProfile?.config.autoSubmitKey {
                try? await Task.sleep(for: .milliseconds(80))
                autoSubmit.submit(autoSubmitKey)
            }
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

    private func activeProfile(for appBundleID: String?) -> VoiceAppProfile? {
        guard let appBundleID,
              let profile = try? appProfiles?.fetch(bundleID: appBundleID),
              profile.config.isEnabled
        else {
            return nil
        }
        return profile
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
        { [weak self] in
            Task { @MainActor in
                self?.cancelCurrentOperation()
            }
        }
    }

    private func makeStopAction() -> () -> Void {
        { [weak self] in
            Task { @MainActor in
                await self?.stopRecordingAndPaste()
            }
        }
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
