import AppKit
import CoreGraphics
import Foundation

@MainActor
final class DockLockingController {
    private var mouseMonitor: Any?
    private var hubSettings: DockHubSettings = .default

    func apply(settings: DockHubSettings) {
        hubSettings = settings
        stop()
        guard settings.master.enableDockLocking, AXIsProcessTrusted() else { return }
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            Task { @MainActor in self?.evaluatePointer() }
        }
    }

    func stop() {
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        mouseMonitor = nil
    }

    private func evaluatePointer() {
        guard hubSettings.master.enableDockLocking else { return }
        let screens = NSScreen.screens
        guard screens.count > 1 else { return }

        let lockedID = hubSettings.dockLock.lockedScreenIdentifier
        let lockedIndex = screens.firstIndex { screen in
            screen.displayID.map(String.init) == lockedID || screen.localizedName == lockedID
        } ?? 0

        let frames = screens.map(\.frame)
        let dockEdge = DockPreviewDockPosition.currentEdge()
        let zones = DockLockerGeometry.calculateTriggerZones(
            screenFrames: frames,
            lockedScreenIndex: lockedIndex,
            dockEdge: dockEdge
        )
        let pointer = NSEvent.mouseLocation
        guard let zone = zones.first(where: { $0.rect.contains(pointer) }) else { return }
        if !overrideModifierDown() {
            CGWarpMouseCursorPosition(CGPoint(x: pointer.x + zone.nudgeVector.dx, y: pointer.y + zone.nudgeVector.dy))
        }
    }

    private func overrideModifierDown() -> Bool {
        let flags = NSEvent.modifierFlags
        switch hubSettings.dockLock.overrideModifier {
        case .option: return flags.contains(.option)
        case .control: return flags.contains(.control)
        case .shift: return flags.contains(.shift)
        case .command: return flags.contains(.command)
        }
    }
}

private extension NSScreen {
    var displayID: UInt32? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32
    }
}
