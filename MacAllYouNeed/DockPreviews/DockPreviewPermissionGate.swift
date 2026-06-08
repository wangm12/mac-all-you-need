import CoreGraphics
import Foundation

enum DockPreviewPermissionGate {
    enum Mode: Equatable {
        case fullPreview
        case titlesOnly
    }

    static func currentMode(
        settings: DockPreviewSettings = DockHubSettingsStore.loadPreviews(),
        hub: DockHubSettings = DockHubSettingsStore.load()
    ) -> Mode {
        if hub.advanced.disableImagePreview || !settings.showThumbnails { return .titlesOnly }
        if #available(macOS 14, *) {
            return CGPreflightScreenCaptureAccess() ? .fullPreview : .titlesOnly
        }
        return .titlesOnly
    }

    /// DockDoor `shouldCaptureWindowImages()` — compact mode and permission gate.
    static func shouldCaptureWindowImages(hub: DockHubSettings) -> Bool {
        !hub.advanced.disableImagePreview && screenRecordingGranted()
    }

    static func screenRecordingGranted() -> Bool {
        if #available(macOS 14, *) {
            return CGPreflightScreenCaptureAccess()
        }
        return false
    }

    static func requestScreenRecordingIfNeeded() {
        if #available(macOS 14, *), !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
        }
    }
}
