import Foundation

public enum AppGroupSettings {
    public static let defaultsSuiteOverrideEnvironmentKey = "MAYN_USER_DEFAULTS_SUITE_OVERRIDE"

    public private(set) static var defaults: UserDefaults = defaults(for: ProcessInfo.processInfo.environment)

    public static func overrideDefaultsForCurrentProcess(_ defaults: UserDefaults) {
        self.defaults = defaults
    }

    static func defaults(for environment: [String: String]) -> UserDefaults {
        if let suite = environment[defaultsSuiteOverrideEnvironmentKey], !suite.isEmpty {
            return UserDefaults(suiteName: suite) ?? .standard
        }
        if let overridePath = environment[AppGroup.containerOverrideEnvironmentKey], !overridePath.isEmpty {
            let suite = "com.macallyouneed.appgroup-override.\(stableSuiteSuffix(for: overridePath))"
            return UserDefaults(suiteName: suite) ?? .standard
        }
        if environment["XCTestBundlePath"] != nil
            || environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestSessionIdentifier"] != nil
        {
            return .standard
        }
        return UserDefaults(suiteName: AppGroup.identifier) ?? .standard
    }

    private static func stableSuiteSuffix(for value: String) -> String {
        let allowed = CharacterSet.alphanumerics
        let scalars = value.unicodeScalars.map { scalar -> String in
            allowed.contains(scalar) ? String(scalar) : "-"
        }
        let suffix = scalars.joined().trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return String(suffix.prefix(96))
    }
}
