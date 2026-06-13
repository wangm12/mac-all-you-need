import AppKit
import ApplicationServices
import Core
import Foundation

/// Resolves the frontmost Finder folder path via Accessibility, with an AppleScript fallback
/// when AX document attributes are empty (common on recent macOS Finder builds).
enum FolderHistoryFinderPathResolver {
    static func resolve(
        pid: pid_t,
        axReader: FolderHistoryAXReader,
        appleScriptFallback: @escaping () -> String? = appleScriptFrontWindowPath
    ) -> String? {
        if let path = axPath(pid: pid, axReader: axReader) { return path }
        return appleScriptFallback()
    }

    private static func axPath(pid: pid_t, axReader: FolderHistoryAXReader) -> String? {
        let app = AXUIElementCreateApplication(pid)
        var focusedValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &focusedValue) == .success,
           let window = focusedValue,
           CFGetTypeID(window) == AXUIElementGetTypeID()
        {
            let axWindow = window as! AXUIElement
            if let path = documentPathSearchingDescendants(axWindow, axReader: axReader) {
                return path
            }
        }
        var windowsValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowsValue) == .success,
              let windows = windowsValue as? [AXUIElement]
        else { return nil }
        for window in windows {
            if let path = documentPathSearchingDescendants(window, axReader: axReader) {
                return path
            }
        }
        return nil
    }

    private static func documentPathSearchingDescendants(
        _ element: AXUIElement,
        axReader: FolderHistoryAXReader,
        depth: Int = 0
    ) -> String? {
        if let path = axReader.documentPath(for: element) { return path }
        guard depth < 8 else { return nil }
        var childrenValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue) == .success
        else { return nil }
        guard let children = childrenValue as? [AXUIElement] else { return nil }
        for child in children {
            if let path = documentPathSearchingDescendants(child, axReader: axReader, depth: depth + 1) {
                return path
            }
        }
        return nil
    }

    static func appleScriptFrontWindowPath() -> String? {
        let source = """
        tell application "Finder"
          if (count of Finder windows) is 0 then return ""
          try
            return POSIX path of (target of front window as alias)
          on error
            return ""
          end try
        end tell
        """
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return nil }
        let result = script.executeAndReturnError(&error)
        guard error == nil else { return nil }
        let path = result.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !path.isEmpty else { return nil }
        return FolderPathNormalizer.normalize(path)
    }
}
