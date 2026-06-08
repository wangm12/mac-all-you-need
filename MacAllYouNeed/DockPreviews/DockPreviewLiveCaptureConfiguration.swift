import Foundation

enum DockPreviewLiveCaptureContext: Equatable {
    case dockHover
    case windowSwitcher
}

/// Resolved ScreenCaptureKit stream parameters from hub settings (dock vs switcher).
struct DockPreviewLiveCaptureConfiguration: Equatable {
    var streamWidth: Int
    var streamHeight: Int
    var frameRate: Int
    var keepAliveSec: Int

    static func resolve(hub: DockHubSettings, context: DockPreviewLiveCaptureContext) -> Self {
        let quality: DockLivePreviewQuality
        let frameRate: DockLivePreviewFrameRate
        switch context {
        case .dockHover:
            quality = hub.advanced.dockLivePreviewQuality
            frameRate = hub.advanced.dockLivePreviewFrameRate
        case .windowSwitcher:
            quality = hub.advanced.switcherLivePreviewQuality
            frameRate = hub.advanced.switcherLivePreviewFrameRate
        }
        let (width, height) = Self.dimensions(for: quality)
        let keepAlive = hub.advanced.livePreviewStreamKeepAlive > 0
            ? hub.advanced.livePreviewStreamKeepAlive
            : hub.previews.liveStreamKeepAliveSec
        return DockPreviewLiveCaptureConfiguration(
            streamWidth: width,
            streamHeight: height,
            frameRate: frameRate.rawValue,
            keepAliveSec: keepAlive
        )
    }

    private static func dimensions(for quality: DockLivePreviewQuality) -> (Int, Int) {
        switch quality {
        case .thumbnail, .low:
            return (240, 150)
        case .standard:
            return (320, 200)
        case .high:
            return (360, 225)
        case .retina, .native:
            return (480, 300)
        }
    }
}
