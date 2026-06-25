import ApplicationServices
import Foundation

struct EditorWindowProvider: WindowHubTabProvider {
    private static let editorBundleIDs: Set<String> = [
        "com.todesktop.230313mzl4w4u92", // Cursor
        "com.microsoft.VSCode",
    ]

    let providerName = "editor-window"

    func matches(bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier else { return false }
        return Self.editorBundleIDs.contains(bundleIdentifier)
    }

    func capabilities(for bundleIdentifier: String?) -> TabCapability {
        matches(bundleIdentifier: bundleIdentifier) ? [.list, .focus] : []
    }

    func tabs(
        pid: pid_t,
        windowID: CGWindowID,
        windowElement: AXUIElement,
        timeoutNanoseconds: UInt64
    ) async -> [WindowHubTabProbe] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: Self.editorTabs(from: windowElement))
            }
        }
    }

    private static func editorTabs(from windowElement: AXUIElement) -> [WindowHubTabProbe] {
        var titleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(windowElement, kAXTitleAttribute as CFString, &titleRef)
        let title = (titleRef as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Editor"
        return [
            WindowHubTabProbe(
                key: "editor-window",
                title: title,
                domain: nil,
                isActive: true,
                isPinned: false,
                isAudible: false,
                isPrivate: false,
                axElement: windowElement
            ),
        ]
    }
}
