import Foundation

enum DockPreviewSortOrder: String, Codable, CaseIterable, Identifiable {
    case recentlyUsed
    case titleAscending
    case titleDescending

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .recentlyUsed: "Recently used"
        case .titleAscending: "Title (A–Z)"
        case .titleDescending: "Title (Z–A)"
        }
    }
}

enum DockPreviewLiveQuality: String, Codable, CaseIterable, Identifiable {
    case low, medium, high
    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

enum DockPreviewLiveFrameRate: Int, Codable, CaseIterable, Identifiable {
    case fps10 = 10
    case fps15 = 15
    case fps24 = 24
    var id: Int { rawValue }
    var displayName: String { "\(rawValue) fps" }
}

struct DockPreviewSettings: Codable, Equatable {
    var showThumbnails: Bool
    var hoverDelayMS: Int
    var fadeOutDurationMS: Int
    var dismissInactivityMS: Int
    var anchorToDockIcon: Bool
    var bufferFromDock: Int
    var thumbnailCacheLifespanSec: Int
    var thumbnailScale: Double
    var enableLivePreview: Bool
    var livePreviewQuality: DockPreviewLiveQuality
    var livePreviewFrameRate: DockPreviewLiveFrameRate
    var liveStreamKeepAliveSec: Int
    var currentSpaceOnly: Bool
    var currentMonitorOnly: Bool
    var sortOrder: DockPreviewSortOrder
    var includeHiddenMinimized: Bool
    var showWindowlessApps: Bool
    var groupAppInstances: Bool
    var ignoreSingleWindowApps: Bool
    var keepPreviewOnAppQuit: Bool
    var enableFolderWidget: Bool
    var folderShowHiddenFiles: Bool
    var preventDockAutoHideWhileOpen: Bool
    var skipDelayWhenPanelVisible: Bool
    /// Append-only worklog under App Group `worklogs/dock-previews/` for debugging hover/dismiss behavior.
    var enableWorklog: Bool

    static let `default` = DockPreviewSettings(
        showThumbnails: true,
        hoverDelayMS: 500,
        fadeOutDurationMS: 400,
        dismissInactivityMS: 200,
        anchorToDockIcon: true,
        bufferFromDock: -20,
        thumbnailCacheLifespanSec: 30,
        thumbnailScale: 1.0,
        enableLivePreview: false,
        livePreviewQuality: .medium,
        livePreviewFrameRate: .fps24,
        liveStreamKeepAliveSec: 0,
        currentSpaceOnly: false,
        currentMonitorOnly: false,
        sortOrder: .recentlyUsed,
        includeHiddenMinimized: true,
        showWindowlessApps: false,
        groupAppInstances: false,
        ignoreSingleWindowApps: false,
        keepPreviewOnAppQuit: false,
        enableFolderWidget: false,
        folderShowHiddenFiles: false,
        preventDockAutoHideWhileOpen: false,
        skipDelayWhenPanelVisible: false,
        enableWorklog: true
    )

    var hoverDelay: TimeInterval { TimeInterval(hoverDelayMS) / 1000 }
    var fadeOutDuration: TimeInterval { TimeInterval(fadeOutDurationMS) / 1000 }
    var dismissInactivity: TimeInterval { TimeInterval(dismissInactivityMS) / 1000 }
    var thumbnailCacheLifespan: TimeInterval { TimeInterval(thumbnailCacheLifespanSec) }
}
