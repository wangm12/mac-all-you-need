import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Foundation

/// Dock scroll, dock click hide/minimize, and related mouse gestures (DockDoor `DockObserver` event tap subset).
@MainActor
final class DockGestureController {
    private weak var hoverObserver: DockHoverObserver?
    private weak var panelController: DockPreviewPanelController?
    private var hubSettings: DockHubSettings = .default
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var lastScrollActionTime = Date.distantPast
    private var lastHoveredPID: pid_t?
    private var lastHoveredWasFrontmost = false
    private let scrollDebounce: TimeInterval = 0.25
    private let titleBarScroll = DockTitleBarScrollController()
    private let mainBundleID = Bundle.main.bundleIdentifier

    init(hoverObserver: DockHoverObserver, panelController: DockPreviewPanelController) {
        self.hoverObserver = hoverObserver
        self.panelController = panelController
    }

    func apply(settings: DockHubSettings) {
        hubSettings = settings
        stop()
        let needsTap = settings.gestures.enableDockScrollGesture
            || settings.gestures.enableTitleBarScrollGesture
            || settings.interaction.hideAllOnDockClick
            || settings.interaction.enableCmdRightClickQuit
        guard needsTap, AXIsProcessTrusted() else { return }
        installEventTap()
    }

    func stop() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        eventTap = nil
        runLoopSource = nil
    }

    func noteHoverBegan(pid: pid_t) {
        lastHoveredPID = pid
        lastHoveredWasFrontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
    }

    func noteHoverEnded() {
        lastHoveredPID = nil
        lastHoveredWasFrontmost = false
    }

    private func installEventTap() {
        var mask: CGEventMask = 0
        mask |= 1 << CGEventType.scrollWheel.rawValue
        mask |= 1 << CGEventType.leftMouseDown.rawValue
        mask |= 1 << CGEventType.rightMouseDown.rawValue

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let controller = Unmanaged<DockGestureController>.fromOpaque(refcon).takeUnretainedValue()
                return controller.handleEvent(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .scrollWheel:
            return handleScrollWheel(event)
        case .leftMouseDown, .rightMouseDown:
            return handleMouseDown(type: type, event: event)
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func handleScrollWheel(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        if hubSettings.gestures.enableTitleBarScrollGesture,
           titleBarScroll.handleScroll(event, settings: hubSettings.gestures)
        {
            return nil
        }
        guard hubSettings.gestures.enableDockScrollGesture else {
            return Unmanaged.passUnretained(event)
        }
        guard DockPreviewDockPosition.isMouseInDockRegion(padding: 48) else {
            return Unmanaged.passUnretained(event)
        }
        guard let info = hoverObserver?.currentAppHoverInfo(), info.pid != 0,
              let app = NSRunningApplication(processIdentifier: info.pid)
        else { return Unmanaged.passUnretained(event) }

        let deltaY = event.getDoubleValueField(.scrollWheelEventDeltaAxis1)
        guard abs(deltaY) > 0.1 else { return Unmanaged.passUnretained(event) }

        let nsEvent = NSEvent(cgEvent: event)
        let natural = nsEvent?.isDirectionInvertedFromDevice ?? false
        let normalized = natural ? -deltaY : deltaY

        if isMediaApp(app.bundleIdentifier),
           hubSettings.gestures.dockScrollMediaBehavior == .adjustVolume
        {
            adjustSystemVolume(delta: normalized)
            return nil
        }

        let now = Date()
        guard now.timeIntervalSince(lastScrollActionTime) >= scrollDebounce else { return nil }
        lastScrollActionTime = now

        if normalized > 0 {
            if app.isHidden { app.unhide() }
            app.activate()
        } else {
            switch hubSettings.gestures.dockScrollBehavior {
            case .activateHide:
                if hubSettings.interaction.dockClickAction == .hide {
                    app.hide()
                } else {
                    hideAllWindows(for: app)
                }
            case .bringToCurrentSpace:
                DockPreviewSpaceMover.moveAppWindowsToCurrentSpace(for: app)
            }
        }
        panelController?.dismiss(animated: true)
        return nil
    }

    private func handleMouseDown(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard let info = hoverObserver?.currentAppHoverInfo(), info.pid != 0,
              let app = NSRunningApplication(processIdentifier: info.pid)
        else { return Unmanaged.passUnretained(event) }

        if app.bundleIdentifier == mainBundleID { return Unmanaged.passUnretained(event) }

        let flags = event.flags
        if type == .rightMouseDown,
           flags.contains(.maskCommand),
           hubSettings.interaction.enableCmdRightClickQuit
        {
            app.terminate()
            panelController?.dismiss(animated: true)
            return nil
        }

        guard type == .leftMouseDown,
              hubSettings.interaction.hideAllOnDockClick,
              panelController?.mouseIsWithinPreview != true
        else { return Unmanaged.passUnretained(event) }

        let pid = app.processIdentifier
        let wasFrontmost = lastHoveredPID == pid ? lastHoveredWasFrontmost
            : NSWorkspace.shared.frontmostApplication?.processIdentifier == pid

        Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .milliseconds(150))
            self.panelController?.dismiss(animated: true)

            let windows = await DockWindowDiscovery.fetchWindows(
                for: pid,
                settings: self.hubSettings.previews,
                bundleIdentifier: app.bundleIdentifier
            )
            guard !windows.isEmpty else { return }

            let hasMinimized = windows.contains(where: \.isMinimized) || app.isHidden
            if hasMinimized, self.hubSettings.interaction.restoreAllMinimizedOnDockClick {
                if app.isHidden { app.unhide() }
                app.activate()
                for entry in windows where entry.isMinimized {
                    DockPreviewWindowActions.unminimize(entry: entry)
                }
            } else if wasFrontmost {
                if self.hubSettings.interaction.dockClickAction == .hide {
                    app.hide()
                } else {
                    for entry in windows where !entry.isMinimized {
                        DockPreviewWindowActions.minimize(entry: entry)
                    }
                }
            }
        }
        return Unmanaged.passUnretained(event)
    }

    private func hideAllWindows(for app: NSRunningApplication) {
        Task {
            let windows = await DockWindowDiscovery.fetchWindows(
                for: app.processIdentifier,
                settings: hubSettings.previews,
                bundleIdentifier: app.bundleIdentifier
            )
            for entry in windows where !entry.isMinimized {
                DockPreviewWindowActions.minimize(entry: entry)
            }
        }
    }

    private func isMediaApp(_ bundleID: String?) -> Bool {
        bundleID == "com.spotify.client" || bundleID == "com.apple.Music"
    }

    private func adjustSystemVolume(delta: Double) {
        let step = Int(delta > 0 ? 6 : -6)
        let script = """
        set currentVolume to output volume of (get volume settings)
        set volume output volume (currentVolume + \(step))
        """
        NSAppleScript(source: script)?.executeAndReturnError(nil)
    }
}
