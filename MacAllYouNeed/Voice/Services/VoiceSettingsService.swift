import Core
import Foundation
import Observation
import Platform

/// Encapsulates Voice ASR-provider and cleanup-provider settings reads,
/// writes, validation, and connectivity tests. All operations are stateless
/// with respect to AppController — they read/write UserDefaults stores and
/// the system Keychain, and never touch live runtime objects (coordinator,
/// retention runner, stores).
@MainActor
@Observable
final class VoiceSettingsService {

    // MARK: - ASR Provider Settings

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

    /// Saves ASR settings and hands off the provider switch to the supplied
    /// coordinator so the running engine is updated immediately.
    func applyVoiceASRSettings(
        _ settings: VoiceASRSettings,
        coordinator: VoiceCoordinator
    ) {
        VoiceASRSettingsStore.save(settings)
        coordinator.applyASRProvider(settings.providerKind, keychain: SystemKeychain())
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

    func applyVoiceASRProviderSettings(
        asrSettings: VoiceASRSettings,
        groqSettings: GroqASRSettings,
        groqAPIKey: String,
        coordinator: VoiceCoordinator
    ) throws {
        let cloudModelID = VoiceCloudASRModelID(groqModelID: groqSettings.modelID) ?? .groqWhisperLargeV3Turbo
        try applyVoiceASRProviderSettings(
            asrSettings: asrSettings,
            cloudSettings: VoiceCloudASRSettings(modelID: cloudModelID, languageHint: groqSettings.languageHint),
            cloudAPIKey: groqAPIKey,
            coordinator: coordinator
        )
    }

    func applyVoiceASRProviderSettings(
        asrSettings: VoiceASRSettings,
        cloudSettings: VoiceCloudASRSettings,
        cloudAPIKey: String,
        coordinator: VoiceCoordinator
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
                applyVoiceASRSettings(asrSettings, coordinator: coordinator)
            }
        }
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

    // MARK: - Cleanup Provider Settings

    func voiceCleanupSettings() -> VoiceCleanupSettings {
        VoiceCleanupSettingsStore.load()
    }

    func voiceCleanupAPIKey(for provider: VoiceCleanupProviderKind) -> String {
        let keyStore = VoiceCleanupKeyStore(keychain: SystemKeychain())
        return (try? keyStore.apiKey(for: provider)) ?? ""
    }

    /// Saves cleanup settings+key and notifies the coordinator so the live
    /// pipeline switches providers immediately.
    func applyVoiceCleanupSettings(
        _ settings: VoiceCleanupSettings,
        apiKey: String,
        coordinator: VoiceCoordinator
    ) throws {
        let keyStore = VoiceCleanupKeyStore(keychain: SystemKeychain())
        try keyStore.saveAPIKey(apiKey, for: settings.provider)
        VoiceCleanupSettingsStore.save(settings)
        coordinator.applyCleanupSettings(settings)
    }

    func disableVoiceCleanup(coordinator: VoiceCoordinator) {
        var settings = VoiceCleanupSettingsStore.load()
        settings.isEnabled = false
        VoiceCleanupSettingsStore.save(settings)
        coordinator.applyCleanupSettings(settings)
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

    // MARK: - Private helpers

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
}

// MARK: - Errors

enum VoiceCleanupSettingsTestError: LocalizedError {
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

enum VoiceASRProviderSettingsError: LocalizedError {
    case validationFailed(String)

    var errorDescription: String? {
        switch self {
        case let .validationFailed(message):
            message
        }
    }
}
