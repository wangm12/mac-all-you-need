import Foundation

public enum AppGroupSettings {
    public static let defaults: UserDefaults = {
        let environment = ProcessInfo.processInfo.environment
        if environment["XCTestBundlePath"] != nil
            || environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestSessionIdentifier"] != nil
        {
            return .standard
        }
        return UserDefaults(suiteName: AppGroup.identifier) ?? .standard
    }()
}
