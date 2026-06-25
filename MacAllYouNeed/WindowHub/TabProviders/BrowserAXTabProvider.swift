import ApplicationServices
import Foundation

struct BrowserAXTabProvider: WindowHubTabProvider {
    private static let browserBundleIDs: Set<String> = [
        "com.google.Chrome",
        "com.google.Chrome.canary",
        "com.apple.Safari",
        "company.thebrowser.Browser",
        "org.mozilla.firefox",
        "com.microsoft.edgemac",
        "com.brave.Browser",
        "com.vivaldi.Vivaldi",
    ]

    let providerName = "browser-ax"

    func matches(bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier else { return false }
        return Self.browserBundleIDs.contains(bundleIdentifier)
    }

    func capabilities(for bundleIdentifier: String?) -> TabCapability {
        matches(bundleIdentifier: bundleIdentifier) ? .browserAX : []
    }

    func tabs(
        pid: pid_t,
        windowID: CGWindowID,
        windowElement: AXUIElement,
        timeoutNanoseconds: UInt64
    ) async -> [WindowHubTabProbe] {
        let budget = max(timeoutNanoseconds, 250_000_000)
        return await withTaskGroup(of: [WindowHubTabProbe].self) { group in
            group.addTask {
                await withCheckedContinuation { continuation in
                    DispatchQueue.global(qos: .userInitiated).async {
                        let tabs = Self.collectTabs(from: windowElement)
                        continuation.resume(returning: tabs)
                    }
                }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: budget)
                return []
            }
            let first = await group.next() ?? []
            group.cancelAll()
            return first
        }
    }

    private static func collectTabs(from windowElement: AXUIElement) -> [WindowHubTabProbe] {
        // Chrome/Safari may expose several AXTabGroups; the tab strip is the
        // richest one. Pick the group that yields the most tabs, then fall back
        // to walking the whole window if no group produced anything.
        var best: [WindowHubTabProbe] = []
        for group in tabGroups(in: windowElement) {
            var candidate: [WindowHubTabProbe] = []
            walkTabs(in: group, into: &candidate)
            if candidate.count > best.count { best = candidate }
        }
        if best.isEmpty {
            walkTabs(in: windowElement, into: &best)
        }
        return best
    }

    private static func tabGroups(in element: AXUIElement) -> [AXUIElement] {
        var groups: [AXUIElement] = []
        if role(of: element) == "AXTabGroup" { groups.append(element) }
        if let children = children(of: element) {
            for child in children {
                groups.append(contentsOf: tabGroups(in: child))
            }
        }
        return groups
    }

    private static func walkTabs(in element: AXUIElement, into results: inout [WindowHubTabProbe]) {
        let role = role(of: element)
        if role == "AXTab" || role == "AXRadioButton" {
            let rawTitle = stringAttribute(element, kAXTitleAttribute)
                ?? stringAttribute(element, kAXDescriptionAttribute)
                ?? stringAttribute(element, "AXHelp")
            let trimmed = rawTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
            // Keep every tab so the count is accurate; loading tabs can report an
            // empty AXTitle, but they are still real tabs the user wants to see.
            let title = (trimmed?.isEmpty == false) ? trimmed! : "Untitled tab"
            let selected = boolAttribute(element, kAXSelectedAttribute) ?? false
            let key = "\(ObjectIdentifier(element).hashValue)"
            results.append(
                WindowHubTabProbe(
                    key: key,
                    title: title,
                    domain: domain(from: title),
                    isActive: selected,
                    isPinned: false,
                    isAudible: false,
                    isPrivate: title.localizedCaseInsensitiveContains("private"),
                    axElement: element
                )
            )
        }
        guard let children = children(of: element) else { return }
        for child in children {
            walkTabs(in: child, into: &results)
        }
    }

    private static func domain(from title: String) -> String? {
        guard let url = URL(string: title), let host = url.host else { return nil }
        return host
    }

    private static func role(of element: AXUIElement) -> String? {
        stringAttribute(element, kAXRoleAttribute)
    }

    private static func children(of element: AXUIElement) -> [AXUIElement]? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success else {
            return nil
        }
        return value as? [AXUIElement]
    }

    private static func stringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func boolAttribute(_ element: AXUIElement, _ attribute: String) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? Bool
    }
}
