import Foundation

public struct ReminderSettings: Codable, Equatable, Sendable {
    public var defaultListID: String?
    public var spokenPrefixEnabled: Bool
    public var upcomingIntervalDays: Int

    /// Voice Reminders on/off is owned by `FeatureID.voiceReminders` in FeatureRuntime,
    /// not this struct. `spokenPrefixEnabled` only controls the "remind me to…" promotion.
    public static let `default` = ReminderSettings(
        defaultListID: nil,
        spokenPrefixEnabled: true,
        upcomingIntervalDays: 7
    )

    public init(
        defaultListID: String?,
        spokenPrefixEnabled: Bool,
        upcomingIntervalDays: Int
    ) {
        self.defaultListID = defaultListID
        self.spokenPrefixEnabled = spokenPrefixEnabled
        self.upcomingIntervalDays = upcomingIntervalDays
    }

    private enum CodingKeys: String, CodingKey {
        case defaultListID
        case spokenPrefixEnabled
        case upcomingIntervalDays
        case isEnabled
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        defaultListID = try container.decodeIfPresent(String.self, forKey: .defaultListID)
        spokenPrefixEnabled = try container.decodeIfPresent(Bool.self, forKey: .spokenPrefixEnabled) ?? true
        upcomingIntervalDays = try container.decodeIfPresent(Int.self, forKey: .upcomingIntervalDays) ?? 7
        _ = try container.decodeIfPresent(Bool.self, forKey: .isEnabled)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(defaultListID, forKey: .defaultListID)
        try container.encode(spokenPrefixEnabled, forKey: .spokenPrefixEnabled)
        try container.encode(upcomingIntervalDays, forKey: .upcomingIntervalDays)
    }
}
