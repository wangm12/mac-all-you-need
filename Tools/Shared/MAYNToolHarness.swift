import AppKit
import Foundation

/// Shared CLI harness utilities used by TypelessImport and VoiceTrainingExport.
enum MAYNToolHarness {

    // MARK: - App-running check

    /// Returns `true` when Mac All You Need is currently running.
    static func isMAYNRunning() -> Bool {
        NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == "com.macallyouneed.app"
        }
    }

    // MARK: - Path helpers

    /// Expands a tilde-prefixed path string and returns a file URL.
    static func expandPath(_ raw: String, isDirectory: Bool = false) -> URL {
        let expanded = NSString(string: raw).expandingTildeInPath
        return URL(fileURLWithPath: expanded, isDirectory: isDirectory)
    }

    // MARK: - Container validation

    /// Validates that `container` is the real Mac All You Need App Group container
    /// (not a fallback sandbox path) and that the clipboard database file exists.
    ///
    /// Returns normally on success; throws `MAYNToolHarnessError.fallbackContainer`
    /// when validation fails.
    static func validateMAYNContainer(_ container: URL) throws {
        let path = container.path
        let isGroupContainer = path.contains(
            "/Library/Group Containers/group.com.macallyouneed.shared"
        )
        let isFallback = path.contains("/MacAllYouNeed-")
        if isFallback || !isGroupContainer {
            throw MAYNToolHarnessError.fallbackContainer(container)
        }
        let dbPath = container.appendingPathComponent("databases/clipboard.sqlite").path
        guard FileManager.default.fileExists(atPath: dbPath) else {
            throw MAYNToolHarnessError.fallbackContainer(container)
        }
    }
}

// MARK: - Errors

enum MAYNToolHarnessError: Error, CustomStringConvertible {
    case fallbackContainer(URL)

    var description: String {
        switch self {
        case .fallbackContainer(let url):
            return """
            Import/export target is not the Mac All You Need App Group container:
              \(url.path)
            Pass --mayn-container pointing at \
            ~/Library/Group Containers/group.com.macallyouneed.shared
            """
        }
    }
}
