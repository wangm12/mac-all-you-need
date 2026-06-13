import AppKit
import ApplicationServices
import Foundation

/// Move windows to the current desktop space (DockDoor `WindowSpaces.move` subset).
enum DockPreviewSpaceMover {
    typealias SpaceID = UInt64

    @MainActor
    static func moveAppWindowsToCurrentSpace(for app: NSRunningApplication) {
        guard let spaceID = currentManagedSpaceID(at: NSEvent.mouseLocation) else { return }
        Task {
            let settings = DockHubSettingsStore.load().previews
            let entries = await DockWindowDiscovery.fetchWindows(
                for: app.processIdentifier,
                settings: settings,
                bundleIdentifier: app.bundleIdentifier
            )
            await MainActor.run {
                var movedAny = false
                for entry in entries where !entry.title.isEmpty {
                    if moveWindow(entry.id, to: spaceID) { movedAny = true }
                }
                guard movedAny else { return }
                if app.isHidden { app.unhide() }
                app.activate()
                if let first = entries.first(where: { !$0.isMinimized && !$0.title.isEmpty }) {
                    Task { await DockPreviewRaiseService().raise(entry: first, settings: settings) }
                }
            }
        }
    }

    static func moveWindowToCurrentSpace(_ windowID: CGWindowID) -> Bool {
        guard let spaceID = currentManagedSpaceID(at: NSEvent.mouseLocation) else { return false }
        return moveWindow(windowID, to: spaceID)
    }

    static func moveWindow(_ windowID: CGWindowID, to spaceID: SpaceID) -> Bool {
        guard let operationClass = NSClassFromString("SLSBridgedMoveWindowsToManagedSpaceOperation") else {
            return false
        }
        let initSelector = NSSelectorFromString("initWithWindows:spaceID:")
        let performSelector = NSSelectorFromString("performWithWMBridgeDelegate")
        guard let allocated = (operationClass as AnyObject).perform(NSSelectorFromString("alloc"))?.takeUnretainedValue(),
              allocated.responds(to: initSelector)
        else { return false }

        typealias InitFn = @convention(c) (AnyObject, Selector, NSArray, UInt64) -> AnyObject
        let initFn = unsafeBitCast(allocated.method(for: initSelector), to: InitFn.self)
        let operation = initFn(
            allocated,
            initSelector,
            [NSNumber(value: windowID)] as NSArray,
            spaceID
        )
        guard operation.responds(to: performSelector) else { return false }
        typealias PerformFn = @convention(c) (AnyObject, Selector) -> Void
        let performFn = unsafeBitCast(operation.method(for: performSelector), to: PerformFn.self)
        performFn(operation, performSelector)
        return true
    }

    private static func currentManagedSpaceID(at mouseLocation: NSPoint) -> SpaceID? {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main
        else { return nil }
        let spaces = DockPreviewSpaceQuery.activeSpaceIDs()
        guard let first = spaces.first else { return nil }
        _ = screen
        return SpaceID(first)
    }
}
