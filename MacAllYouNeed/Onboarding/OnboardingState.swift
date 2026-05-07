import Core
import Foundation

enum OnboardingState: String {
    case notStarted, welcome, accessibility, fullDiskAccess, notifications, sync, ready, completed

    static let key = "onboardingState"

    static func load() -> OnboardingState {
        OnboardingState(rawValue: AppGroupSettings.defaults.string(forKey: key) ?? "") ?? .notStarted
    }

    func save() { AppGroupSettings.defaults.set(rawValue, forKey: Self.key) }
    static func reset() { AppGroupSettings.defaults.removeObject(forKey: key) }
}
