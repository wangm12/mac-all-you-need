import Foundation
import os

public enum Logging {
    private static let prefix = "com.macallyouneed"

    public static func subsystem(for feature: String) -> String {
        "\(prefix).\(feature)"
    }

    public static func logger(for feature: String, category: String = "default") -> Logger {
        Logger(subsystem: subsystem(for: feature), category: category)
    }
}
