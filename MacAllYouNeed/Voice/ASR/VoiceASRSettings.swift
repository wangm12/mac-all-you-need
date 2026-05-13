import Core
import FluidAudio
import Foundation

enum VoiceASRLanguageHint: String, CaseIterable, Codable, Equatable, Identifiable {
    case automatic
    case chinese
    case english

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .automatic:
            "Auto"
        case .chinese:
            "Chinese"
        case .english:
            "English"
        }
    }

    var qwen3Language: Qwen3AsrConfig.Language? {
        switch self {
        case .automatic:
            nil
        case .chinese:
            .chinese
        case .english:
            .english
        }
    }
}

struct VoiceASRSettings: Codable, Equatable {
    var languageHint: VoiceASRLanguageHint

    static let `default` = VoiceASRSettings(languageHint: .automatic)
}

enum VoiceASRSettingsStore {
    private static let key = "voice.asr.settings.v1"

    static func load(from defaults: UserDefaults = AppGroupSettings.defaults) -> VoiceASRSettings {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(VoiceASRSettings.self, from: data)
        else {
            return .default
        }
        return decoded
    }

    static func save(_ settings: VoiceASRSettings, to defaults: UserDefaults = AppGroupSettings.defaults) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: key)
    }
}
