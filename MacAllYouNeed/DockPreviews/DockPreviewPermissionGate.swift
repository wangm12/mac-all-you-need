import CoreGraphics
import Foundation

enum DockPreviewPermissionGate {
    enum Mode: Equatable {
        case fullPreview
        case titlesOnly
    }

    static func currentMode(settings: DockPreviewSettings = DockHubSettingsStore.loadPreviews()) -> Mode {
        guard settings.showThumbnails else { return .titlesOnly }
        if #available(macOS 14, *) {
            return CGPreflightScreenCaptureAccess() ? .fullPreview : .titlesOnly
        }
        return .titlesOnly
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
