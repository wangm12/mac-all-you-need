import AppKit
import Core
import FeatureCore
import Foundation

struct DockGesturesSettings: Codable, Equatable {
    var enableDockScroll: Bool
    var enableTitleBarScroll: Bool
    var enablePreviewGestures: Bool

    static let `default` = DockGesturesSettings(
        enableDockScroll: false,
        enableTitleBarScroll: false,
        enablePreviewGestures: false
    )
}

enum DockGesturesSettingsStore {
    private static let key = "dockGestures.settings"

    static func load() -> DockGesturesSettings {
        guard let data = AppGroupSettings.defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(DockGesturesSettings.self, from: data)
        else { return .default }
        return decoded
    }

    static func save(_ settings: DockGesturesSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        AppGroupSettings.defaults.set(data, forKey: key)
    }
}

@MainActor
final class DockGesturesRuntime {
    private(set) var isEnabled = false
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var settings = DockGesturesSettings.default

    func applyEnabled(_ enabled: Bool, settings: DockGesturesSettings = DockGesturesSettingsStore.load()) {
        self.settings = settings
        stop()
        isEnabled = enabled && settings.enableDockScroll
        guard isEnabled, AXIsProcessTrusted() else { return }
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
        isEnabled = false
    }

    private func installEventTap() {
        let mask = (1 << CGEventType.scrollWheel.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, refcon in
                guard type == .scrollWheel, let refcon else { return Unmanaged.passUnretained(event) }
                let runtime = Unmanaged<DockGesturesRuntime>.fromOpaque(refcon).takeUnretainedValue()
                return runtime.handleScroll(event)
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

    private func handleScroll(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        guard settings.enableDockScroll else { return Unmanaged.passUnretained(event) }
        let location = event.location
        guard DockPreviewDockPosition.isMouseInDockRegion(padding: 48) else {
            return Unmanaged.passUnretained(event)
        }
        let delta = event.getDoubleValueField(.scrollWheelEventDeltaAxis1)
        guard abs(delta) > 0.1 else { return Unmanaged.passUnretained(event) }
        NotificationCenter.default.post(
            name: .dockGesturesScrollInDock,
            object: nil,
            userInfo: ["delta": delta]
        )
        return nil
    }
}

extension Notification.Name {
    static let dockGesturesScrollInDock = Notification.Name("dockGesturesScrollInDock")
}

struct DockGesturesFeatureActivator: FeatureActivator {
    func activate() async throws {}
    func deactivate() async throws {}
}
