import Foundation

public enum AppGroup {
    public static let identifier = "group.com.macallyouneed.shared"
    public static let containerOverrideEnvironmentKey = "MAYN_APP_GROUP_CONTAINER_OVERRIDE"

    public static var containerURLOverride: URL?

    public static func entitledContainerURL() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    public static func isUsingFallbackContainer() -> Bool {
        containerURLOverride == nil
            && ProcessInfo.processInfo.environment[containerOverrideEnvironmentKey] == nil
            && entitledContainerURL() == nil
    }

    public static func containerURL(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let override = containerURLOverride { return override }
        if let overridePath = environment[containerOverrideEnvironmentKey], !overridePath.isEmpty {
            let expanded = NSString(string: overridePath).expandingTildeInPath
            let url = URL(fileURLWithPath: expanded, isDirectory: true)
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }
        if let url = entitledContainerURL() { return url }
        let fallback = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacAllYouNeed-\(NSUserName())", isDirectory: true)
        try? FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true)
        return fallback
    }
}
