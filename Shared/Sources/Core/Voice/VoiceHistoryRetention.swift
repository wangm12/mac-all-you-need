import Foundation

public enum VoiceHistoryRetention: String, CaseIterable, Hashable, Sendable {
    case forever
    case days1
    case days7
    case days30
    case days90

    public var storageKey: String {
        switch self {
        case .forever: return "forever"
        case .days1:   return "1d"
        case .days7:   return "7d"
        case .days30:  return "30d"
        case .days90:  return "90d"
        }
    }

    public init(storageKey: String) {
        switch storageKey {
        case "forever": self = .forever
        case "1d":      self = .days1
        case "7d":      self = .days7
        case "30d":     self = .days30
        case "90d":     self = .days90
        default:        self = .forever
        }
    }

    public var maxAgeSeconds: TimeInterval? {
        switch self {
        case .forever: return nil
        case .days1:   return 1 * 86_400
        case .days7:   return 7 * 86_400
        case .days30:  return 30 * 86_400
        case .days90:  return 90 * 86_400
        }
    }

    public var displayTitle: String {
        switch self {
        case .forever: return "Forever"
        case .days1:   return "Last 1 day"
        case .days7:   return "Last 7 days"
        case .days30:  return "Last 30 days"
        case .days90:  return "Last 90 days"
        }
    }
}
