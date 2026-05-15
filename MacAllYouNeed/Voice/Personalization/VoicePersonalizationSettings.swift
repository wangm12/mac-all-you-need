import Core
import Foundation

struct VoicePersonalizationSettings: Codable, Equatable {
    var learnFromEditsEnabled: Bool
    var rollingCacheDays: Int
    var rollingCacheMaxSamples: Int

    static let `default` = VoicePersonalizationSettings(
        learnFromEditsEnabled: true,
        rollingCacheDays: 30,
        rollingCacheMaxSamples: 50
    )

    init(
        learnFromEditsEnabled: Bool = true,
        rollingCacheDays: Int = 30,
        rollingCacheMaxSamples: Int = 50
    ) {
        self.learnFromEditsEnabled = learnFromEditsEnabled
        self.rollingCacheDays = rollingCacheDays
        self.rollingCacheMaxSamples = rollingCacheMaxSamples
    }

    private enum CodingKeys: String, CodingKey {
        case learnFromEditsEnabled
        case rollingCacheDays
        case rollingCacheMaxSamples
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        learnFromEditsEnabled = try container.decodeIfPresent(Bool.self, forKey: .learnFromEditsEnabled)
            ?? VoicePersonalizationSettings.default.learnFromEditsEnabled
        rollingCacheDays = try container.decodeIfPresent(Int.self, forKey: .rollingCacheDays)
            ?? VoicePersonalizationSettings.default.rollingCacheDays
        rollingCacheMaxSamples = try container.decodeIfPresent(Int.self, forKey: .rollingCacheMaxSamples)
            ?? VoicePersonalizationSettings.default.rollingCacheMaxSamples
    }
}

enum VoicePersonalizationSettingsStore {
    static let key = "voice.personalization.settings.v1"

    static func load(from defaults: UserDefaults = AppGroupSettings.defaults) -> VoicePersonalizationSettings {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(VoicePersonalizationSettings.self, from: data)
        else {
            return .default
        }
        return decoded
    }

    static func save(_ settings: VoicePersonalizationSettings, to defaults: UserDefaults = AppGroupSettings.defaults) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: key)
    }
}
