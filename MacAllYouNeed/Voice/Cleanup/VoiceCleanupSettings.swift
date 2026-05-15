import Core
import Foundation

enum VoiceCleanupProviderKind: String, CaseIterable, Codable, Equatable, Identifiable {
    case anthropic
    case openAICompatible
    case ollama

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .anthropic:
            "Anthropic"
        case .openAICompatible:
            "OpenAI compatible"
        case .ollama:
            "Ollama"
        }
    }

    var defaultModel: String {
        switch self {
        case .anthropic:
            "claude-haiku-4-5"
        case .openAICompatible:
            "gpt-5-nano"
        case .ollama:
            "qwen2.5:7b-instruct"
        }
    }

    var defaultBaseURLString: String {
        switch self {
        case .anthropic:
            "https://api.anthropic.com"
        case .openAICompatible:
            "https://api.openai.com/v1"
        case .ollama:
            "http://localhost:11434/v1"
        }
    }

    var requiresAPIKey: Bool {
        switch self {
        case .anthropic, .openAICompatible:
            true
        case .ollama:
            false
        }
    }
}

struct VoiceCleanupSettings: Codable, Equatable {
    var isEnabled: Bool
    var provider: VoiceCleanupProviderKind
    var model: String
    var baseURLString: String
    var timeoutSeconds: Int

    static let `default` = VoiceCleanupSettings(
        isEnabled: false,
        provider: .anthropic,
        model: VoiceCleanupProviderKind.anthropic.defaultModel,
        baseURLString: VoiceCleanupProviderKind.anthropic.defaultBaseURLString,
        timeoutSeconds: 7
    )

    var effectiveModel: String {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? provider.defaultModel : trimmed
    }

    var effectiveBaseURLString: String {
        let trimmed = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? provider.defaultBaseURLString : trimmed
    }

    var normalizedTimeoutSeconds: Int {
        max(1, timeoutSeconds)
    }
}

enum VoiceCleanupSettingsStore {
    static let key = "voice.cleanup.settings.v1"

    static func load(from defaults: UserDefaults = AppGroupSettings.defaults) -> VoiceCleanupSettings {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(VoiceCleanupSettings.self, from: data)
        else {
            return .default
        }
        return decoded
    }

    static func save(_ settings: VoiceCleanupSettings, to defaults: UserDefaults = AppGroupSettings.defaults) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: key)
    }
}

final class VoiceCleanupKeyStore {
    private let keychain: KeychainBackend

    init(keychain: KeychainBackend) {
        self.keychain = keychain
    }

    func apiKey(for provider: VoiceCleanupProviderKind) throws -> String? {
        guard let data = try keychain.get(account(for: provider)),
              let value = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : value
    }

    func saveAPIKey(_ apiKey: String, for provider: VoiceCleanupProviderKind) throws {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            try keychain.delete(account(for: provider))
            return
        }
        try keychain.set(Data(apiKey.utf8), for: account(for: provider))
    }

    private func account(for provider: VoiceCleanupProviderKind) -> String {
        "voice.cleanup.api-key.\(provider.rawValue).v1"
    }
}

enum VoiceCleanupProviderFactory {
    static func makeProvider(
        settings: VoiceCleanupSettings,
        keyStore: VoiceCleanupKeyStore
    ) throws -> (any VoiceLLMProvider)? {
        try makeProvider(settings: settings) { provider in
            try keyStore.apiKey(for: provider)
        }
    }

    static func makeProvider(
        settings: VoiceCleanupSettings,
        apiKey: String
    ) throws -> (any VoiceLLMProvider)? {
        try makeProvider(settings: settings) { _ in
            let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }

    static func makeTextGenerationProvider(
        settings: VoiceCleanupSettings,
        keyStore: VoiceCleanupKeyStore
    ) throws -> (any VoiceTextGenerationProvider)? {
        guard settings.isEnabled else { return nil }
        switch settings.provider {
        case .anthropic:
            guard let apiKey = try? keyStore.apiKey(for: .anthropic),
                  let baseURL = URL(string: settings.effectiveBaseURLString)
            else { return nil }
            return AnthropicVoiceProvider(apiKey: apiKey, model: settings.effectiveModel, baseURL: baseURL)
        case .openAICompatible:
            guard let apiKey = try? keyStore.apiKey(for: .openAICompatible),
                  let baseURL = URL(string: settings.effectiveBaseURLString)
            else { return nil }
            return OpenAICompatibleVoiceProvider(apiKey: apiKey, model: settings.effectiveModel, baseURL: baseURL)
        case .ollama:
            guard let baseURL = URL(string: settings.effectiveBaseURLString) else { return nil }
            return OpenAICompatibleVoiceProvider(
                apiKey: (try? keyStore.apiKey(for: .ollama)) ?? "",
                model: settings.effectiveModel,
                baseURL: baseURL
            )
        }
    }

    private static func makeProvider(
        settings: VoiceCleanupSettings,
        apiKeyForProvider: (VoiceCleanupProviderKind) throws -> String?
    ) throws -> (any VoiceLLMProvider)? {
        guard settings.isEnabled else { return nil }

        switch settings.provider {
        case .anthropic:
            guard let apiKey = try apiKeyForProvider(.anthropic),
                  let baseURL = URL(string: settings.effectiveBaseURLString)
            else {
                return nil
            }
            return AnthropicVoiceProvider(
                apiKey: apiKey,
                model: settings.effectiveModel,
                baseURL: baseURL
            )

        case .openAICompatible:
            guard let apiKey = try apiKeyForProvider(.openAICompatible),
                  let baseURL = URL(string: settings.effectiveBaseURLString)
            else {
                return nil
            }
            return OpenAICompatibleVoiceProvider(
                apiKey: apiKey,
                model: settings.effectiveModel,
                baseURL: baseURL
            )

        case .ollama:
            guard let baseURL = URL(string: settings.effectiveBaseURLString) else {
                return nil
            }
            return try OpenAICompatibleVoiceProvider(
                apiKey: apiKeyForProvider(.ollama) ?? "",
                model: settings.effectiveModel,
                baseURL: baseURL
            )
        }
    }
}
