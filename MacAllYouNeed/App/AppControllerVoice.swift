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

    func groqASRAPIKey() -> String {
        let keyStore = GroqASRKeyStore(keychain: SystemKeychain())
        return (try? keyStore.apiKey()) ?? ""
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
        let normalizedGroqAPIKey = groqAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if let validationMessage = VoiceASRProviderApplyPlan.validationMessage(
            providerKind: asrSettings.providerKind,
            apiKey: normalizedGroqAPIKey
        ) {
            throw VoiceASRProviderSettingsError.validationFailed(validationMessage)
        }

        for step in VoiceASRProviderApplyPlan.steps(for: asrSettings.providerKind) {
            switch step {
            case .saveGroqSettings:
                try applyGroqASRSettings(groqSettings, apiKey: normalizedGroqAPIKey)
            case .applyASRSettings:
                applyVoiceASRSettings(asrSettings)
            }
        }
    }

    func applyGroqASRSettings(_ settings: GroqASRSettings, apiKey: String) throws {
        let keyStore = GroqASRKeyStore(keychain: SystemKeychain())
        try keyStore.saveAPIKey(apiKey)
        GroqASRSettingsStore.save(settings)
    }

    func applyGroqASRSettings(_ settings: GroqASRSettings) {
        GroqASRSettingsStore.save(settings)
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
}

private enum VoiceCleanupSettingsTestError: LocalizedError {
    case timedOut

    var errorDescription: String? {
        switch self {
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
