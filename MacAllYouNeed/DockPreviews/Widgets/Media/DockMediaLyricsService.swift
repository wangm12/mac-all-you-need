import AppKit
import Foundation

/// Fetches synced lyrics for Music / Spotify via AppleScript (DockDoor subset).
enum DockMediaLyricsService {
    static func fetchLyrics(bundleIdentifier: String?) async -> String? {
        guard let bundleIdentifier else { return nil }
        let script: String?
        switch bundleIdentifier {
        case "com.apple.Music", "com.apple.iTunes":
            script = """
            tell application "Music"
                if player state is playing or player state is paused then
                    return name of current track
                end if
            end tell
            """
        case "com.spotify.client":
            script = """
            tell application "Spotify"
                if player state is playing or player state is paused then
                    return name of current track
                end if
            end tell
            """
        default:
            return nil
        }
        guard let script else { return nil }
        return await runAppleScript(script)
    }

    private static func runAppleScript(_ source: String) async -> String? {
        await Task.detached {
            var error: NSDictionary?
            guard let script = NSAppleScript(source: source) else { return nil }
            let result = script.executeAndReturnError(&error)
            guard error == nil else { return nil }
            return result.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
        }.value
    }
}
