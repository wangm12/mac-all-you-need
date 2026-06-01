import AppKit
import ApplicationServices
import Foundation

// MARK: - CGS / CoreDock private symbols (reimplemented; behavior aligned with DockDoor)

typealias DockPreviewCGSConnectionID = UInt32
typealias DockPreviewCGSSpaceID = UInt64
typealias DockPreviewCGSSpaceMask = UInt64

private let kDockPreviewCGSAllSpacesMask: DockPreviewCGSSpaceMask = 0xFFFF_FFFF_FFFF_FFFF

@_silgen_name("CGSMainConnectionID")
private func dockPreviewCGSMainConnectionID() -> DockPreviewCGSConnectionID

@_silgen_name("CGSCopySpacesForWindows")
private func dockPreviewCGSCopySpacesForWindows(
    _ cid: DockPreviewCGSConnectionID,
    _ mask: DockPreviewCGSSpaceMask,
    _ windowIDs: CFArray
) -> CFArray?

@_silgen_name("CGSCopyManagedDisplaySpaces")
private func dockPreviewCGSCopyManagedDisplaySpaces(_ cid: DockPreviewCGSConnectionID) -> CFArray?

@_silgen_name("CoreDockGetAutoHideEnabled")
private func dockPreviewCoreDockGetAutoHideEnabled() -> Bool

@_silgen_name("CoreDockSetAutoHideEnabled")
private func dockPreviewCoreDockSetAutoHideEnabled(_ flag: Bool)

enum DockPreviewSpaceQuery {
    static func activeSpaceIDs() -> Set<Int> {
        let connection = dockPreviewCGSMainConnectionID()
        if let displays = dockPreviewCGSCopyManagedDisplaySpaces(connection) as? [[String: AnyObject]] {
            var result = Set<Int>()
            for display in displays {
                if let currentSpace = display["Current Space"] as? [String: AnyObject],
                   let spaceID = (currentSpace["ManagedSpaceID"] as? NSNumber)?.intValue
                {
                    result.insert(spaceID)
                }
            }
            if !result.isEmpty { return result }
        }
        return inferActiveSpaceIDsFromOnScreenWindows()
    }

    static func spaceIDs(for windowID: CGWindowID) -> [Int] {
        let connection = dockPreviewCGSMainConnectionID()
        let arr: CFArray = [NSNumber(value: UInt32(windowID))] as CFArray
        guard let spaces = dockPreviewCGSCopySpacesForWindows(
            connection,
            kDockPreviewCGSAllSpacesMask,
            arr
        ) as? [NSNumber] else { return [] }
        return spaces.map(\.intValue)
    }

    static func windowBelongsToActiveSpaces(_ windowID: CGWindowID, activeSpaceIDs: Set<Int>) -> Bool {
        let windowSpaces = Set(spaceIDs(for: windowID))
        if !windowSpaces.isEmpty {
            return !windowSpaces.isDisjoint(with: activeSpaceIDs)
        }
        return false
    }

    private static func inferActiveSpaceIDsFromOnScreenWindows() -> Set<Int> {
        var result = Set<Int>()
        guard let list = CGWindowListCopyWindowInfo([.excludeDesktopElements], kCGNullWindowID) as? [[String: AnyObject]]
        else { return result }
        for desc in list {
            let layer = (desc[kCGWindowLayer as String] as? NSNumber)?.intValue ?? -1
            let isOnscreen = (desc[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? false
            guard layer == 0, isOnscreen else { continue }
            let wid = CGWindowID((desc[kCGWindowNumber as String] as? NSNumber)?.uint32Value ?? 0)
            for space in spaceIDs(for: wid) {
                result.insert(space)
            }
        }
        return result
    }
}

enum DockPreviewDockVisibility {
    /// False when the frontmost app is fullscreen (Dock is hidden) or the Dock has zero thickness.
    static func isDockVisible() -> Bool {
        if let frontmost = NSWorkspace.shared.frontmostApplication,
           DockPreviewFullscreenDetection.isAppFullscreen(frontmost)
        {
            return false
        }
        return estimatedDockThickness() > 0
    }

    private static func estimatedDockThickness() -> CGFloat {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return 0 }
        let edge = DockPreviewDockPosition.currentEdge()
        switch edge {
        case .bottom:
            return screen.visibleFrame.minY - screen.frame.minY
        case .left:
            return screen.visibleFrame.minX - screen.frame.minX
        case .right:
            return screen.frame.maxX - screen.visibleFrame.maxX
        }
    }
}

@MainActor
final class DockPreviewDockAutoHideManager {
    private var wasAutoHideEnabled: Bool?
    private var isManaging = false

    func preventHidingIfNeeded(settings: DockPreviewSettings) {
        guard settings.preventDockAutoHideWhileOpen else { return }
        let current = dockPreviewCoreDockGetAutoHideEnabled()
        if current {
            wasAutoHideEnabled = current
            isManaging = true
            dockPreviewCoreDockSetAutoHideEnabled(false)
        }
    }

    func restoreIfNeeded() {
        guard isManaging, let wasEnabled = wasAutoHideEnabled else { return }
        dockPreviewCoreDockSetAutoHideEnabled(wasEnabled)
        wasAutoHideEnabled = nil
        isManaging = false
    }
}

enum DockPreviewFullscreenDetection {
    static func isAppFullscreen(_ app: NSRunningApplication) -> Bool {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement]
        else { return false }
        for window in windows {
            var fullscreenRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(window, "AXFullScreen" as CFString, &fullscreenRef) == .success,
               (fullscreenRef as? Bool) == true
            {
                return true
            }
        }
        return false
    }
}
