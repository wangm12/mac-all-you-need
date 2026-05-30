import Foundation

/// Pure rules deciding whether a folder path should never be recorded in history.
public enum FolderHistorySkipRules {
    /// Folders that should never be recorded regardless of user configuration.
    static var alwaysSkipped: Set<String> {
        [
            "/", "/tmp", "/var", "/private/tmp", "/private/var",
            NSHomeDirectory() + "/Library",
            NSHomeDirectory() + "/Library/Caches",
        ]
    }

    public static func shouldSkip(path: String, exclusions: Set<String>) -> Bool {
        if alwaysSkipped.contains(path) { return true }
        if exclusions.contains(path) { return true }
        // Skip everything under ~/Library unless the user explicitly excluded only it.
        let libraryPath = NSHomeDirectory() + "/Library"
        if path.hasPrefix(libraryPath + "/") { return true }
        // Skip hidden directories (last component begins with ".").
        let components = path.split(separator: "/")
        if components.last?.hasPrefix(".") == true { return true }
        return false
    }
}
