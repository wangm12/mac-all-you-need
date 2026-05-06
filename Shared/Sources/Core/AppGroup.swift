import Foundation

public enum AppGroup {
    public static let identifier = "group.com.macallyouneed.shared"

    public static var containerURLOverride: URL?

    public static func entitledContainerURL() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    public static func isUsingFallbackContainer() -> Bool {
        containerURLOverride == nil && entitledContainerURL() == nil
    }

    public static func containerURL() -> URL {
        if let override = containerURLOverride { return override }
        if let url = entitledContainerURL() { return url }
        let fallback = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacAllYouNeed-\(NSUserName())", isDirectory: true)
        try? FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true)
        return fallback
    }
}
