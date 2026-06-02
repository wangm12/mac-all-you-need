import AppKit
import ApplicationServices
import Foundation

/// DockDoor / alt-tab AX window discovery (`AXUIElement.allWindows` + `windowsByBruteForce`).
enum DockPreviewAXWindowDiscovery {
    static func allWindows(
        pid: pid_t,
        appElement: AXUIElement,
        app: NSRunningApplication?,
        api: any DockPreviewPrivateAPI,
        cgCandidates: [[String: AnyObject]]
    ) -> [AXUIElement] {
        var elements: [AXUIElement] = []
        if let windows = copyWindowsAttribute(appElement) {
            elements.append(contentsOf: windows)
        }
        elements.append(contentsOf: windowsByBruteForce(
            pid: pid,
            app: app,
            api: api,
            cgCandidates: cgCandidates
        ))
        return dedupe(elements)
    }

    private static func windowsByBruteForce(
        pid: pid_t,
        app: NSRunningApplication?,
        api: any DockPreviewPrivateAPI,
        cgCandidates: [[String: AnyObject]]
    ) -> [AXUIElement] {
        guard let app else { return [] }

        var token = Data(count: 20)
        token.replaceSubrange(0 ..< 4, with: withUnsafeBytes(of: pid) { Data($0) })
        token.replaceSubrange(4 ..< 8, with: withUnsafeBytes(of: Int32(0)) { Data($0) })
        token.replaceSubrange(8 ..< 12, with: withUnsafeBytes(of: Int32(0x636F_636F)) { Data($0) })

        var results: [AXUIElement] = []
        for axID: UInt64 in 0 ..< 1000 {
            token.replaceSubrange(12 ..< 20, with: withUnsafeBytes(of: axID) { Data($0) })
            guard let element = api.axElementWithRemoteToken(token) else { continue }

            let windowID = api.axWindowID(for: element) ?? 0
            let attributes = DockPreviewWindowCandidateAttributes(axWindow: element)
            let level = windowID == 0
                ? nil
                : DockPreviewCGWindowValidation.level(for: windowID, in: cgCandidates)
            if DockPreviewWindowCandidateDiscriminator.isPotentialAXWindow(
                app: app,
                level: level,
                attributes: attributes
            ) {
                results.append(element)
            }
        }
        return results
    }

    private static func copyWindowsAttribute(_ appElement: AXUIElement) -> [AXUIElement]? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value) == .success else {
            return nil
        }
        return value as? [AXUIElement]
    }

    private static func dedupe(_ elements: [AXUIElement]) -> [AXUIElement] {
        var result: [AXUIElement] = []
        for element in elements where !result.contains(where: { CFEqual($0, element) }) {
            result.append(element)
        }
        return result
    }
}
