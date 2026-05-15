import Foundation

public enum AppGroupSettings {
    public static let defaults: UserDefaults = defaults(for: ProcessInfo.processInfo.environment)

    static func defaults(for environment: [String: String]) -> UserDefaults {
        if environment["XCTestBundlePath"] != nil
            || environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestSessionIdentifier"] != nil
            || environment[AppGroup.containerOverrideEnvironmentKey] != nil
        {
            return .standard
        }
        return UserDefaults(suiteName: AppGroup.identifier) ?? .standard
    }
}
