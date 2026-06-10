import Core
import Foundation

enum VoiceCleanupProviderKind: String, CaseIterable, Codable, Equatable, Identifiable {
    case anthropic
    case openAICompatible
    case groq
    case gemini
    case ollama
    case omlx

    var id: String {
        rawValue
    }

    /// Provider name for pickers, settings summaries, and validation copy (not a specific model ID).
    var label: String {
        switch self {
        case .anthropic:
            "Anthropic"
        case .openAICompatible:
            "OpenAI"
        case .groq:
            "Groq"
        case .gemini:
            "Google"
        case .ollama:
            "Ollama"
        case .omlx:
            "oMLX"
        }
    }

    var defaultModel: String {
        switch self {
        case .anthropic:
            "claude-haiku-4-5"
        case .openAICompatible:
            "gpt-5-nano"
        case .groq:
            "openai/gpt-oss-20b"
        case .gemini:
            "gemini-2.5-flash"
        case .ollama:
            "qwen2.5:3b-instruct"
        case .omlx:
            "qwen2.5-3b-instruct"
        }
    }

    var defaultBaseURLString: String {
        switch self {
        case .anthropic:
            "https://api.anthropic.com"
        case .openAICompatible:
            "https://api.openai.com/v1"
        case .groq:
            "https://api.groq.com/openai/v1"
        case .gemini:
            "https://generativelanguage.googleapis.com/v1beta/openai/"
        case .ollama:
            "http://localhost:11434/v1"
        case .omlx:
            "http://127.0.0.1:8000/v1"
        }
    }

    var requiresAPIKey: Bool {
        switch self {
        case .anthropic, .openAICompatible, .groq, .gemini:
            true
        case .ollama, .omlx:
            false
        }
    }
}

enum VoiceCleanupLatencyPolicy: String, CaseIterable, Codable, Equatable, Identifiable {
    case balanced2s
    case qualityFirst

    var id: String { rawValue }

    var label: String {
        switch self {
        case .balanced2s:
            "Balanced 2s"
        case .qualityFirst:
            "Quality First"
        }
    }

    var subtitle: String {
        switch self {
        case .balanced2s:
            "Keeps release-to-paste responsive by falling back locally when the cleanup budget is gone."
        case .qualityFirst:
            "Allows the full configured timeout before falling back."
        }
    }
}

struct VoiceCleanupSettings: Codable, Equatable {
    var isEnabled: Bool
    var provider: VoiceCleanupProviderKind
    var model: String
    var baseURLString: String
    var timeoutSeconds: Int
    var latencyPolicy: VoiceCleanupLatencyPolicy

    static let `default` = VoiceCleanupSettings(
        isEnabled: false,
        provider: .anthropic,
        model: VoiceCleanupProviderKind.anthropic.defaultModel,
        baseURLString: VoiceCleanupProviderKind.anthropic.defaultBaseURLString,
        timeoutSeconds: 7,
        latencyPolicy: .balanced2s
    )

    init(
        isEnabled: Bool,
        provider: VoiceCleanupProviderKind,
        model: String,
        baseURLString: String,
        timeoutSeconds: Int,
        latencyPolicy: VoiceCleanupLatencyPolicy = .balanced2s
    ) {
        self.isEnabled = isEnabled
        self.provider = provider
        self.model = model
        self.baseURLString = baseURLString
        self.timeoutSeconds = timeoutSeconds
        self.latencyPolicy = latencyPolicy
    }

    private enum CodingKeys: String, CodingKey {
        case isEnabled
        case provider
        case model
        case baseURLString
        case timeoutSeconds
        case latencyPolicy
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? Self.default.isEnabled
        provider = try container.decodeIfPresent(VoiceCleanupProviderKind.self, forKey: .provider) ?? Self.default.provider
        model = try container.decodeIfPresent(String.self, forKey: .model) ?? provider.defaultModel
        baseURLString = try container.decodeIfPresent(String.self, forKey: .baseURLString) ?? provider.defaultBaseURLString
        timeoutSeconds = try container.decodeIfPresent(Int.self, forKey: .timeoutSeconds) ?? Self.default.timeoutSeconds
        latencyPolicy = try container.decodeIfPresent(VoiceCleanupLatencyPolicy.self, forKey: .latencyPolicy) ?? .balanced2s
    }

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

enum VoiceCleanupLatencyBudget {
    static let balancedTargetSeconds: TimeInterval = 2.0
    static let minimumRemoteBudgetSeconds: TimeInterval = 0.25

    static func remoteTimeout(
        policy: VoiceCleanupLatencyPolicy,
        elapsedBeforeCleanupSeconds: TimeInterval,
        configuredTimeoutSeconds: Int
    ) -> Duration? {
        let configured = max(1, configuredTimeoutSeconds)
        switch policy {
        case .qualityFirst:
            return .seconds(Int64(configured))
        case .balanced2s:
            let remaining = balancedTargetSeconds - elapsedBeforeCleanupSeconds
            guard remaining >= minimumRemoteBudgetSeconds else { return nil }
            let bounded = min(Double(configured), remaining)
            return .milliseconds(Int64((bounded * 1000).rounded(.down)))
        }
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
            guard let apiKey = try keyStore.apiKey(for: .anthropic),
                  let baseURL = URL(string: settings.effectiveBaseURLString)
            else { return nil }
            return AnthropicVoiceProvider(apiKey: apiKey, model: settings.effectiveModel, baseURL: baseURL)
        case .openAICompatible, .groq, .gemini:
            guard let apiKey = try keyStore.apiKey(for: settings.provider),
                  let baseURL = URL(string: settings.effectiveBaseURLString)
            else { return nil }
            return OpenAICompatibleVoiceProvider(apiKey: apiKey, model: settings.effectiveModel, baseURL: baseURL)
        case .ollama, .omlx:
            guard let baseURL = URL(string: settings.effectiveBaseURLString) else { return nil }
            return OpenAICompatibleVoiceProvider(
                apiKey: try keyStore.apiKey(for: settings.provider) ?? "",
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

        case .openAICompatible, .groq, .gemini:
            guard let apiKey = try apiKeyForProvider(settings.provider),
                  let baseURL = URL(string: settings.effectiveBaseURLString)
            else {
                return nil
            }
            return OpenAICompatibleVoiceProvider(
                apiKey: apiKey,
                model: settings.effectiveModel,
                baseURL: baseURL
            )

        case .ollama, .omlx:
            guard let baseURL = URL(string: settings.effectiveBaseURLString) else {
                return nil
            }
            return try OpenAICompatibleVoiceProvider(
                apiKey: apiKeyForProvider(settings.provider) ?? "",
                model: settings.effectiveModel,
                baseURL: baseURL
            )
        }
    }
}
