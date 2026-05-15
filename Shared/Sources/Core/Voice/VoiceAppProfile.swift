import Foundation

// DEPRECATED: This file is a temporary compile shim used until T7 removes
// the last `VoiceAppProfileStore` references from VoiceCoordinator and
// AppController. The corresponding `app_profiles` table was dropped in
// migration 005-personalization. Personalization data now lives in
// VoicePersonalizationContext / VoicePersonalizationStore.

public struct VoiceAppProfileConfig: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var customPrompt: String
    public var language: VoiceLanguage?
    public var asrEngineID: String?
    public var autoSubmitKey: VoiceAutoSubmitKey

    public init(
        isEnabled: Bool,
        customPrompt: String,
        language: VoiceLanguage?,
        asrEngineID: String?,
        autoSubmitKey: VoiceAutoSubmitKey
    ) {
        self.isEnabled = isEnabled
        self.customPrompt = customPrompt
        self.language = language
        self.asrEngineID = asrEngineID
        self.autoSubmitKey = autoSubmitKey
    }

    public static let `default` = VoiceAppProfileConfig(
        isEnabled: false,
        customPrompt: "",
        language: nil,
        asrEngineID: nil,
        autoSubmitKey: .none
    )
}

public struct VoiceAppProfile: Identifiable, Equatable, Sendable {
    public let id: String
    public let bundleID: String
    public let displayName: String
    public let config: VoiceAppProfileConfig
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        id: String,
        bundleID: String,
        displayName: String,
        config: VoiceAppProfileConfig,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.bundleID = bundleID
        self.displayName = displayName
        self.config = config
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
