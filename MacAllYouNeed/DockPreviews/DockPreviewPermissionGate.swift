import CoreGraphics
import Foundation

enum DockPreviewPermissionGate {
    enum Mode {
        case fullPreview    // thumbnails + titles
        case titlesOnly     // Screen Recording denied — text only
    }

    static func currentMode() -> Mode {
        // CGPreflightScreenCaptureAccess() is available on macOS 14+
        if #available(macOS 14, *) {
            return CGPreflightScreenCaptureAccess() ? .fullPreview : .titlesOnly
        }
        return .titlesOnly
    }

    static func requestIfNeeded() async {
        if #available(macOS 14, *), !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
        }
    }
}
