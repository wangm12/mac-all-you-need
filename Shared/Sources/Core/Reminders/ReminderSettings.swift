import Foundation

public struct ReminderSettings: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var defaultListID: String?
    public var spokenPrefixEnabled: Bool
    public var upcomingIntervalDays: Int

    public static let `default` = ReminderSettings(
        isEnabled: false,
        defaultListID: nil,
        spokenPrefixEnabled: true,
        upcomingIntervalDays: 7
    )

    public init(
        isEnabled: Bool,
        defaultListID: String?,
        spokenPrefixEnabled: Bool,
        upcomingIntervalDays: Int
    ) {
        self.isEnabled = isEnabled
        self.defaultListID = defaultListID
        self.spokenPrefixEnabled = spokenPrefixEnabled
        self.upcomingIntervalDays = upcomingIntervalDays
    }
}
