import Core
import Foundation

// MARK: - Provider kind

enum VoiceASRProviderKind: String, CaseIterable, Codable, Equatable, Identifiable {
    case local
    case groq

    var id: String { rawValue }

    var label: String {
        switch self {
        case .local: "Local (Qwen3)"
        case .groq: "Groq Whisper"
        }
    }

    var subtitle: String {
        switch self {
        case .local: "On-device, private. ~30s max per segment."
        case .groq: "Cloud via Groq. Best code-switching quality. Requires API key."
        }
    }
}

// MARK: - Groq model

enum GroqASRModelID: String, CaseIterable, Codable, Equatable, Identifiable {
    case whisperLargeV3Turbo = "whisper-large-v3-turbo"
    case whisperLargeV3 = "whisper-large-v3"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .whisperLargeV3Turbo: "Whisper Large V3 Turbo"
        case .whisperLargeV3: "Whisper Large V3"
        }
    }

    var subtitle: String {
        switch self {
        case .whisperLargeV3Turbo: "Faster · $0.04/hr · Recommended"
        case .whisperLargeV3: "More accurate · $0.111/hr"
        }
    }
}

// MARK: - Groq settings

struct GroqASRSettings: Codable, Equatable {
    var modelID: GroqASRModelID
    var languageHint: VoiceASRLanguageHint

    static let `default` = GroqASRSettings(
        modelID: .whisperLargeV3Turbo,
        languageHint: .automatic
    )

    /// ISO-639-1 code to send to Groq, or nil for automatic detection.
    var groqLanguageCode: String? {
        switch languageHint {
        case .automatic: nil
        case .chinese: "zh"
        case .english: "en"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case modelID
        case languageHint
    }

    init(modelID: GroqASRModelID = .whisperLargeV3Turbo,
         languageHint: VoiceASRLanguageHint = .automatic) {
        self.modelID = modelID
        self.languageHint = languageHint
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        modelID = try container.decodeIfPresent(GroqASRModelID.self, forKey: .modelID)
            ?? GroqASRSettings.default.modelID
        languageHint = try container.decodeIfPresent(VoiceASRLanguageHint.self, forKey: .languageHint)
            ?? GroqASRSettings.default.languageHint
    }
}

enum GroqASRSettingsStore {
    static let key = "voice.asr.groq.settings.v1"

    static func load(from defaults: UserDefaults = AppGroupSettings.defaults) -> GroqASRSettings {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(GroqASRSettings.self, from: data)
        else { return .default }
        return decoded
    }

    static func save(_ settings: GroqASRSettings, to defaults: UserDefaults = AppGroupSettings.defaults) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: key)
    }
}
