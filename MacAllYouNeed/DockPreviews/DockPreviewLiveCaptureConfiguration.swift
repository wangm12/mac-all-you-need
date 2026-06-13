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
    var queueDepth: Int
    var enableHDR: Bool

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
            keepAliveSec: keepAlive,
            queueDepth: Self.queueDepth(for: quality),
            enableHDR: hub.advanced.enableHDRLivePreview
        )
    }

    private static func queueDepth(for quality: DockLivePreviewQuality) -> Int {
        switch quality {
        case .high, .retina, .native:
            return 5
        case .thumbnail, .low, .standard:
            return 3
        }
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
