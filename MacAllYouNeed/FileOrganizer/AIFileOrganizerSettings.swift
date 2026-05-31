import Core
import Foundation

/// Persisted settings for the AI File Organizer feature.
struct AIFileOrganizerSettings: Codable, Equatable {
    var provider: VoiceCleanupProviderKind
    var model: String
    var baseURLString: String
    var timeoutSeconds: Int
    var latencyPolicy: VoiceCleanupLatencyPolicy
    var namingCaseStyle: CaseStyle
    var maxFilenameLength: Int
    var maxSubfolderDepth: Int
    var watchedFolderPaths: [String]

    static let defaultsKey = "aiFileOrganizer.settings.v1"

    static let `default` = AIFileOrganizerSettings(
        provider: .anthropic,
        model: "",
        baseURLString: "",
        timeoutSeconds: 15,
        latencyPolicy: .balanced2s,
        namingCaseStyle: .titleCase,
        maxFilenameLength: 80,
        maxSubfolderDepth: 2,
        watchedFolderPaths: []
    )

    static func load() -> AIFileOrganizerSettings {
        guard let data = AppGroupSettings.defaults.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode(AIFileOrganizerSettings.self, from: data)
        else { return .default }
        return decoded
    }

    static func save(_ settings: AIFileOrganizerSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        AppGroupSettings.defaults.set(data, forKey: defaultsKey)
    }
}

extension CaseStyle {
    var displayName: String {
        switch self {
        case .titleCase: return "Title Case"
        case .camelCase: return "camelCase"
        case .snakeCase: return "snake_case"
        case .kebabCase: return "kebab-case"
        case .unchanged: return "Unchanged"
        }
    }
}
