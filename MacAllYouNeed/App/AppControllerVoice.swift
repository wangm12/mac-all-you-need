import Core
import Foundation

extension AppController {
    func applyVoiceActivationSettings(_ settings: VoiceActivationSettings) throws {
        try voiceCoordinator.applyActivationSettings(settings)
        VoiceActivationSettingsStore.save(settings)
    }

    func listVoiceDictionaryEntries() -> [VoiceDictionaryEntry] {
        (try? voiceDictionaryStore.list()) ?? []
    }

    func upsertVoiceDictionaryEntry(phrase: String, replacement: String) throws {
        try voiceDictionaryStore.upsert(phrase: phrase, replacement: replacement)
    }

    func deleteVoiceDictionaryEntry(id: String) throws {
        try voiceDictionaryStore.delete(id: id)
    }

    func listRecentVoiceTranscripts(limit: Int = 20) -> [VoiceTranscript] {
        (try? voiceTranscriptStore.listRecent(limit: limit)) ?? []
    }

    func deleteVoiceTranscripts(ids: [String]) throws {
        try voiceTranscriptStore.delete(ids: ids)
    }

    func listPersonalizationContexts() -> [VoicePersonalizationContext] {
        (try? voicePersonalizationStore.listContexts()) ?? []
    }

    func upsertPersonalizationContext(_ draft: VoicePersonalizationContextDraft) throws {
        try voicePersonalizationStore.upsertContext(draft)
    }

    func deletePersonalizationContext(id: String) throws {
        try voicePersonalizationStore.deleteContext(id: id)
    }

    func clearPersonalizationData() throws {
        try voicePersonalizationStore.clearAll()
    }

    func voiceTrainingExampleCount() -> Int {
        (try? voiceTrainingExampleStore.count()) ?? 0
    }

    func clearVoiceTrainingExamples() throws {
        try voiceTrainingExampleStore.clearAll()
    }

    func voicePersonalizationSettings() -> VoicePersonalizationSettings {
        VoicePersonalizationSettingsStore.load()
    }

    func applyVoicePersonalizationSettings(_ settings: VoicePersonalizationSettings) {
        VoicePersonalizationSettingsStore.save(settings)
    }

    func voiceASRSettings() -> VoiceASRSettings {
        VoiceASRSettingsStore.load()
    }

    func voiceGroqASRSettings() -> GroqASRSettings {
        GroqASRSettingsStore.load()
    }

    func voiceCloudASRSettings() -> VoiceCloudASRSettings {
        VoiceCloudASRSettingsStore.load()
    }

    func groqASRAPIKey() -> String {
        cloudASRAPIKey(for: .groq)
    }

    func cloudASRAPIKey(for providerKind: VoiceASRProviderKind) -> String {
        let keyStore = VoiceCloudASRKeyStore(keychain: SystemKeychain())
        return (try? keyStore.apiKey(for: providerKind)) ?? ""
    }

    func applyVoiceASRSettings(_ settings: VoiceASRSettings) {
        VoiceASRSettingsStore.save(settings)
        voiceCoordinator.applyASRProvider(settings.providerKind, keychain: SystemKeychain())
    }

    func applyVoiceASRProviderSettings(
        asrSettings: VoiceASRSettings,
        groqSettings: GroqASRSettings,
        groqAPIKey: String
    ) throws {
        let cloudModelID = VoiceCloudASRModelID(groqModelID: groqSettings.modelID) ?? .groqWhisperLargeV3Turbo
        try applyVoiceASRProviderSettings(
            asrSettings: asrSettings,
            cloudSettings: VoiceCloudASRSettings(modelID: cloudModelID, languageHint: groqSettings.languageHint),
            cloudAPIKey: groqAPIKey
        )
    }

    func applyVoiceASRProviderSettings(
        asrSettings: VoiceASRSettings,
        cloudSettings: VoiceCloudASRSettings,
        cloudAPIKey: String
    ) throws {
        let effectiveCloudSettings = asrSettings.providerKind.isCloud
            ? cloudSettings.updating(modelID: cloudSettings.modelID(for: asrSettings.providerKind))
            : cloudSettings
        let normalizedCloudAPIKey = cloudAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if let validationMessage = VoiceASRProviderApplyPlan.validationMessage(
            providerKind: asrSettings.providerKind,
            apiKey: normalizedCloudAPIKey
        ) {
            throw VoiceASRProviderSettingsError.validationFailed(validationMessage)
        }

        for step in VoiceASRProviderApplyPlan.steps(for: asrSettings.providerKind) {
            switch step {
            case .saveCloudSettings:
                try applyCloudASRSettings(effectiveCloudSettings, apiKey: normalizedCloudAPIKey)
            case .applyASRSettings:
                applyVoiceASRSettings(asrSettings)
            }
        }
    }

    func applyGroqASRSettings(_ settings: GroqASRSettings, apiKey: String) throws {
        let cloudModelID = VoiceCloudASRModelID(groqModelID: settings.modelID) ?? .groqWhisperLargeV3Turbo
        try applyCloudASRSettings(
            VoiceCloudASRSettings(modelID: cloudModelID, languageHint: settings.languageHint),
            apiKey: apiKey
        )
    }

    func applyGroqASRSettings(_ settings: GroqASRSettings) {
        let cloudModelID = VoiceCloudASRModelID(groqModelID: settings.modelID) ?? .groqWhisperLargeV3Turbo
        applyCloudASRSettings(VoiceCloudASRSettings(modelID: cloudModelID, languageHint: settings.languageHint))
    }

    func applyCloudASRSettings(_ settings: VoiceCloudASRSettings, apiKey: String) throws {
        let keyStore = VoiceCloudASRKeyStore(keychain: SystemKeychain())
        try keyStore.saveAPIKey(apiKey, for: settings.modelID.providerKind)
        VoiceCloudASRSettingsStore.save(settings)
    }

    func applyCloudASRSettings(_ settings: VoiceCloudASRSettings) {
        VoiceCloudASRSettingsStore.save(settings)
    }

    func testGroqASRSettings(_ settings: GroqASRSettings, apiKey: String) async -> String {
        let normalizedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedAPIKey.isEmpty else {
            return "API key is required."
        }
        // Use the key in-memory only — do NOT write to Keychain before we know it works.
        let engine = GroqASREngine(
            settings: { settings },
            apiKeyProvider: { normalizedAPIKey }
        )
        let silence = [Float](repeating: 0.0, count: 8000)
        do {
            _ = try await engine.transcribe(
                samples: silence,
                sampleRate: 16000,
                options: VoiceTranscriptionOptions(preferredModelIdentifier: nil)
            )
            return "Connection succeeded."
        } catch GroqASRError.missingAPIKey {
            return "API key not saved."
        } catch let GroqASRError.httpError(code) {
            return "HTTP \(code) — check your API key."
        } catch {
            let msg = error.localizedDescription
            if msg.lowercased().contains("empty") || msg.lowercased().contains("too short") {
                return "Connection succeeded."
            }
            return "Ping failed: \(msg)"
        }
    }

    func testCloudASRSettings(
        _ settings: VoiceCloudASRSettings,
        providerKind: VoiceASRProviderKind,
        apiKey: String
    ) async -> String {
        let normalizedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedAPIKey.isEmpty else {
            return "\(providerKind.apiKeyLabel) is required."
        }
        let engine = VoiceCloudASREngine(
            providerKind: providerKind,
            settings: { settings },
            apiKeyProvider: { requestedProvider in
                requestedProvider == providerKind ? normalizedAPIKey : nil
            }
        )
        let silence = [Float](repeating: 0.0, count: 8000)
        do {
            _ = try await engine.transcribe(
                samples: silence,
                sampleRate: 16000,
                options: VoiceTranscriptionOptions(preferredModelIdentifier: nil)
            )
            return "Connection succeeded."
        } catch let VoiceCloudASRError.httpError(_, code) {
            return "HTTP \(code) - check your API key."
        } catch VoiceCloudASRError.missingAPIKey {
            return "API key not saved."
        } catch {
            let msg = error.localizedDescription
            if msg.lowercased().contains("empty") || msg.lowercased().contains("too short") {
                return "Connection succeeded."
            }
            return "Ping failed: \(msg)"
        }
    }

    func voiceCleanupSettings() -> VoiceCleanupSettings {
        VoiceCleanupSettingsStore.load()
    }

    func voiceCleanupAPIKey(for provider: VoiceCleanupProviderKind) -> String {
        let keyStore = VoiceCleanupKeyStore(keychain: SystemKeychain())
        return (try? keyStore.apiKey(for: provider)) ?? ""
    }

    func applyVoiceCleanupSettings(_ settings: VoiceCleanupSettings, apiKey: String) throws {
        let keyStore = VoiceCleanupKeyStore(keychain: SystemKeychain())
        try keyStore.saveAPIKey(apiKey, for: settings.provider)
        VoiceCleanupSettingsStore.save(settings)
        voiceCoordinator.applyCleanupSettings(settings)
    }

    func disableVoiceCleanup() {
        var settings = VoiceCleanupSettingsStore.load()
        settings.isEnabled = false
        VoiceCleanupSettingsStore.save(settings)
        voiceCoordinator.applyCleanupSettings(settings)
    }

    func validateVoiceCleanupSettings(_ settings: VoiceCleanupSettings, apiKey: String) -> String {
        guard settings.isEnabled else {
            return "AI cleanup is disabled; local cleanup is active."
        }
        guard URL(string: settings.effectiveBaseURLString) != nil else {
            return "Base URL is invalid."
        }
        if settings.provider.requiresAPIKey, apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "API key is required for \(settings.provider.label)."
        }
        if settings.effectiveModel.isEmpty {
            return "Model is required."
        }
        return "Configuration is usable."
    }

    func testVoiceCleanupSettings(_ settings: VoiceCleanupSettings, apiKey: String) async -> String {
        let validation = validateVoiceCleanupSettings(settings, apiKey: apiKey)
        guard validation == "Configuration is usable." else { return validation }

        do {
            guard let provider = try VoiceCleanupProviderFactory.makeProvider(settings: settings, apiKey: apiKey) else {
                return "Provider could not be created."
            }
            let output = try await Self.runVoiceCleanupPing(provider: provider, timeoutSeconds: settings.normalizedTimeoutSeconds)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !output.isEmpty else { return "Provider returned an empty response." }
            return "Ping succeeded: \(output.prefix(80))"
        } catch {
            return "Ping failed: \(error.localizedDescription)"
        }
    }

    func listOllamaCleanupModels(settings: VoiceCleanupSettings) async throws -> [OllamaModel] {
        try await Self.makeOllamaServiceClient(settings: settings).listModels()
    }

    func pullOllamaCleanupModel(settings: VoiceCleanupSettings, model: String) async throws {
        try await Self.makeOllamaServiceClient(settings: settings).pull(model: model)
    }

    func deleteOllamaCleanupModel(settings: VoiceCleanupSettings, model: String) async throws {
        try await Self.makeOllamaServiceClient(settings: settings).delete(model: model)
    }

    func testOllamaCleanupService(settings: VoiceCleanupSettings) async -> String {
        do {
            let models = try await listOllamaCleanupModels(settings: settings)
            if models.isEmpty {
                return "Ollama is reachable. No local models found."
            }
            return "Ollama is reachable. \(models.count) local model\(models.count == 1 ? "" : "s") found."
        } catch {
            return "Ollama check failed: \(error.localizedDescription)"
        }
    }

    private static func makeOllamaServiceClient(settings: VoiceCleanupSettings) throws -> OllamaServiceClient {
        guard let baseURL = URL(string: settings.effectiveBaseURLString) else {
            throw VoiceCleanupSettingsTestError.invalidBaseURL
        }
        return OllamaServiceClient(baseURL: baseURL)
    }

    private static func runVoiceCleanupPing(
        provider: any VoiceLLMProvider,
        timeoutSeconds: Int
    ) async throws -> String {
        let request = VoiceLLMRequest(
            text: "Reply with: ok",
            rawText: "Reply with: ok",
            appBundleID: nil,
            language: .english
        )
        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                try await provider.clean(request)
            }
            group.addTask {
                try await Task.sleep(for: .seconds(Int64(timeoutSeconds)))
                throw VoiceCleanupSettingsTestError.timedOut
            }

            let output = try await group.next() ?? ""
            group.cancelAll()
            return output
        }
    }

    func loadVoiceHistorySettings() -> VoiceHistorySettings {
        VoiceHistorySettings.load(from: AppGroupSettings.defaults)
    }

    func saveVoiceHistorySettings(_ settings: VoiceHistorySettings) {
        settings.save(to: AppGroupSettings.defaults)
        voiceRetentionRunner.sweepNow()
    }

    func retryVoiceTranscript(id: String) async throws -> VoiceTranscript {
        try await voiceCoordinator.retryTranscript(id: id)
    }

    func downloadVoiceAudio(transcript: VoiceTranscript, to url: URL) throws {
        guard let path = transcript.audioPath else {
            throw VoiceRetryError.noAudio
        }
        let wav = try voiceTrainingExampleStore.loadEncryptedAudio(path: path)
        try wav.write(to: url, options: .atomic)
    }

    /// Deletes the transcript row immediately and defers audio-file deletion by 5 seconds.
    /// Returns a token whose `undo()` re-saves the row and cancels the deferred delete.
    func deleteVoiceTranscriptWithUndo(_ transcript: VoiceTranscript) -> VoiceHistoryUndoToken {
        try? voiceTranscriptStore.delete(ids: [transcript.id])

        let id = transcript.id
        let audioPath = transcript.audioPath
        let store = voiceTranscriptStore
        let trainingStore = voiceTrainingExampleStore

        // Defer audio cleanup so undo can restore the row before the file is gone.
        let cleanupTask = Task.detached {
            try? await Task.sleep(for: .seconds(5))
            guard let audioPath else { return }
            // Don't delete if training example store still references the file.
            if let paths = try? trainingStore.allAudioPaths(), paths.contains(audioPath) { return }
            try? FileManager.default.removeItem(atPath: audioPath)
        }

        let undo: () -> Void = { [transcript, store] in
            cleanupTask.cancel()
            _ = try? store.save(
                VoiceTranscriptDraft(
                    startedAt: transcript.startedAt,
                    endedAt: transcript.endedAt,
                    rawText: transcript.rawText,
                    cleanedText: transcript.cleanedText,
                    appBundleID: transcript.appBundleID,
                    language: transcript.language,
                    modelIdentifier: transcript.modelIdentifier,
                    audioPath: transcript.audioPath
                ),
                existingID: id
            )
        }

        return VoiceHistoryUndoToken(
            message: "Transcript deleted",
            undo: undo,
            expiresAt: Date().addingTimeInterval(5)
        )
    }
}

private enum VoiceCleanupSettingsTestError: LocalizedError {
    case invalidBaseURL
    case timedOut

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            "Base URL is invalid."
        case .timedOut:
            "Provider ping timed out."
        }
    }
}

private enum VoiceASRProviderSettingsError: LocalizedError {
    case validationFailed(String)

    var errorDescription: String? {
        switch self {
        case let .validationFailed(message):
            message
        }
    }
}
