import AppKit
import CoreGraphics
import Foundation
import Platform

@MainActor
final class DockLockingController {
    private var mouseMonitor: Any?
    private var screenObserver: Any?
    private var hubSettings: DockHubSettings = .default
    private var cachedTriggerZones: [DockTriggerZone] = []

    func apply(settings: DockHubSettings) {
        hubSettings = settings
        stop()
        guard settings.master.enableDockLocking, AXIsProcessTrusted() else { return }
        refreshTriggerZones()
        guard !cachedTriggerZones.isEmpty else { return }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleScreenConfigChanged() }
        }
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            Task { @MainActor in self?.evaluatePointer() }
        }
    }

    func stop() {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
        screenObserver = nil
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        mouseMonitor = nil
        cachedTriggerZones = []
    }

    private func handleScreenConfigChanged() {
        refreshTriggerZones()
        if cachedTriggerZones.isEmpty {
            if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
            mouseMonitor = nil
        }
    }

    private func refreshTriggerZones() {
        let screens = NSScreen.screens
        guard screens.count > 1 else {
            cachedTriggerZones = []
            return
        }

        let lockedID = hubSettings.dockLock.lockedScreenIdentifier ?? ""
        guard !lockedID.isEmpty else {
            cachedTriggerZones = []
            return
        }

        let lockedIndex = screens.firstIndex { screen in
            screen.displayID.map(String.init) == lockedID || screen.localizedName == lockedID
        }
        guard let lockedIndex else {
            cachedTriggerZones = []
            return
        }

        let dockEdge = DockPreviewDockPosition.currentEdge(for: screens[lockedIndex])
        cachedTriggerZones = DockLockerGeometry.calculateTriggerZones(
            screenFrames: screens.map(\.cgFrame),
            lockedScreenIndex: lockedIndex,
            dockEdge: dockEdge
        )
    }

    private func evaluatePointer() {
        guard hubSettings.master.enableDockLocking, !cachedTriggerZones.isEmpty else { return }
        guard !overrideModifierDown() else { return }

        let pointerCG = DockPreviewDockCoordinates.cgPoint(fromAppKit: NSEvent.mouseLocation)
        guard let zone = cachedTriggerZones.first(where: { $0.rect.contains(pointerCG) }) else { return }

        let cgTarget = CGPoint(
            x: pointerCG.x + zone.nudgeVector.dx,
            y: pointerCG.y + zone.nudgeVector.dy
        )
        CGAssociateMouseAndMouseCursorPosition(0)
        CGWarpMouseCursorPosition(cgTarget)
        CGAssociateMouseAndMouseCursorPosition(1)
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
