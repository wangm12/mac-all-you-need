import ApplicationServices
import Foundation

struct NativeAXTabProvider: WindowHubTabProvider {
    private static let nativeBundleIDs: Set<String> = [
        "com.apple.Terminal",
        "com.apple.finder",
    ]

    let providerName = "native-ax"

    func matches(bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier else { return false }
        return Self.nativeBundleIDs.contains(bundleIdentifier)
    }

    func capabilities(for bundleIdentifier: String?) -> TabCapability {
        guard matches(bundleIdentifier: bundleIdentifier) else { return [] }
        if bundleIdentifier == "com.apple.Terminal" {
            return [.list, .focus, .close, .create]
        }
        return [.list, .focus]
    }

    func tabs(
        pid: pid_t,
        windowID: CGWindowID,
        windowElement: AXUIElement,
        timeoutNanoseconds: UInt64
    ) async -> [WindowHubTabProbe] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: Self.collect(from: windowElement))
            }
        }
    }

    private static func collect(from windowElement: AXUIElement) -> [WindowHubTabProbe] {
        var results: [WindowHubTabProbe] = []
        walk(element: windowElement, into: &results)
        return results
    }

    private static func walk(element: AXUIElement, into results: inout [WindowHubTabProbe]) {
        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        let role = roleRef as? String
        if role == "AXTab" || role == "AXRadioButton" || role == "AXList" {
            var titleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef)
            let title = (titleRef as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let title, !title.isEmpty {
                var selectedRef: CFTypeRef?
                AXUIElementCopyAttributeValue(element, kAXSelectedAttribute as CFString, &selectedRef)
                let selected = (selectedRef as? Bool) ?? false
                results.append(
                    WindowHubTabProbe(
                        key: "\(ObjectIdentifier(element).hashValue)",
                        title: title,
                        domain: nil,
                        isActive: selected,
                        isPinned: false,
                        isAudible: false,
                        isPrivate: false,
                        axElement: element
                    )
                )
            }
        }
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement]
        else { return }
        for child in children {
            walk(element: child, into: &results)
        }
    }
}
