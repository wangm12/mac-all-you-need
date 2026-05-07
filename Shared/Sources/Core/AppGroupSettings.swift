import Foundation

public enum AppGroupSettings {
    public static let defaults: UserDefaults = UserDefaults(suiteName: AppGroup.identifier) ?? .standard
}
