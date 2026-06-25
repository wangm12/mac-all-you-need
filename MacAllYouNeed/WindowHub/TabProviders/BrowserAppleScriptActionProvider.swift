import AppKit
import ApplicationServices
import Foundation

/// AppleScript-backed mutation capabilities for Chromium and Safari.
struct BrowserAppleScriptActionProvider: WindowHubTabProvider {
    private static let scriptableBrowsers: Set<String> = [
        "com.google.Chrome",
        "com.google.Chrome.canary",
        "com.apple.Safari",
        "com.microsoft.edgemac",
        "com.brave.Browser",
    ]

    let providerName = "browser-applescript"

    func matches(bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier else { return false }
        return Self.scriptableBrowsers.contains(bundleIdentifier)
    }

    func capabilities(for bundleIdentifier: String?) -> TabCapability {
        matches(bundleIdentifier: bundleIdentifier) ? .browserScript : []
    }

    func tabs(
        pid: pid_t,
        windowID: CGWindowID,
        windowElement: AXUIElement,
        timeoutNanoseconds: UInt64
    ) async -> [WindowHubTabProbe] {
        // Listing is owned by ChromiumBrowserTabProvider / BrowserAXTabProvider.
        await BrowserAXTabProvider().tabs(
            pid: pid,
            windowID: windowID,
            windowElement: windowElement,
            timeoutNanoseconds: timeoutNanoseconds
        )
    }
}

enum BrowserAppleScriptActions {
    static func closeTab(bundleIdentifier: String, windowIndex: Int, tabIndex: Int) -> Bool {
        let script: String
        switch bundleIdentifier {
        case "com.apple.Safari":
            script = """
            tell application "Safari"
              tell window \(windowIndex)
                close current tab
              end tell
            end tell
            """
        default:
            script = """
            tell application id "\(bundleIdentifier)"
              tell window \(windowIndex)
                close tab \(tabIndex)
              end tell
            end tell
            """
        }
        return run(script)
    }

    private static func run(_ source: String) -> Bool {
        guard let script = NSAppleScript(source: source) else { return false }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        return error == nil
    }
}
