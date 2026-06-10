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
    var useDelayOnlyForInitialOpen: Bool
    var preventPreviewReentryDuringFadeOut: Bool
    // Appearance (DockDoor parity)
    var previewCardWidth: Int
    var previewCardHeight: Int
    var lockAspectRatio: Bool
    var showWindowTitle: Bool
    var showAppNameInHeader: Bool
    var compactModeThreshold: Int
    var showTrafficLightButtons: Bool
    var allowDynamicImageSizing: Bool
    var showPreviewAnimations: Bool
    var previewMaxColumns: Int
    var previewMaxRows: Int
    var globalPaddingMultiplier: Double
    var uniformCardRadius: Bool
    var enableFullSizeHoverPreview: Bool
    var panelBackgroundOpacity: Double
    var appearanceOptions: DockPreviewAppearanceOptions
    var panelBackground: DockPreviewPanelBackgroundOptions
    var hideHoverContainerBackground: Bool
    var detachedSwitcherSearch: Bool
    /// Append-only worklog under App Group `worklogs/dock-previews/` for debugging hover/dismiss behavior.
    var enableWorklog: Bool
    /// Hide native Dock tooltip while hover preview is open (bottom-docked).
    var overlayDockTooltip: Bool
    /// Runtime-only: widen ScreenCaptureKit discovery for switcher/cmd-tab (not persisted in hub settings).
    var useBroadWindowDiscovery: Bool = false

    init(
        showThumbnails: Bool,
        hoverDelayMS: Int,
        fadeOutDurationMS: Int,
        dismissInactivityMS: Int,
        anchorToDockIcon: Bool,
        bufferFromDock: Int,
        thumbnailCacheLifespanSec: Int,
        thumbnailScale: Double,
        enableLivePreview: Bool,
        livePreviewQuality: DockPreviewLiveQuality,
        livePreviewFrameRate: DockPreviewLiveFrameRate,
        liveStreamKeepAliveSec: Int,
        currentSpaceOnly: Bool,
        currentMonitorOnly: Bool,
        sortOrder: DockPreviewSortOrder,
        includeHiddenMinimized: Bool,
        showWindowlessApps: Bool,
        groupAppInstances: Bool,
        ignoreSingleWindowApps: Bool,
        keepPreviewOnAppQuit: Bool,
        enableFolderWidget: Bool,
        folderShowHiddenFiles: Bool,
        preventDockAutoHideWhileOpen: Bool,
        skipDelayWhenPanelVisible: Bool,
        useDelayOnlyForInitialOpen: Bool,
        preventPreviewReentryDuringFadeOut: Bool,
        previewCardWidth: Int,
        previewCardHeight: Int,
        lockAspectRatio: Bool,
        showWindowTitle: Bool,
        showAppNameInHeader: Bool,
        compactModeThreshold: Int,
        showTrafficLightButtons: Bool,
        allowDynamicImageSizing: Bool,
        showPreviewAnimations: Bool,
        previewMaxColumns: Int,
        previewMaxRows: Int,
        globalPaddingMultiplier: Double,
        uniformCardRadius: Bool,
        enableFullSizeHoverPreview: Bool,
        panelBackgroundOpacity: Double,
        appearanceOptions: DockPreviewAppearanceOptions,
        panelBackground: DockPreviewPanelBackgroundOptions,
        hideHoverContainerBackground: Bool,
        detachedSwitcherSearch: Bool,
        enableWorklog: Bool,
        overlayDockTooltip: Bool
    ) {
        self.showThumbnails = showThumbnails
        self.hoverDelayMS = hoverDelayMS
        self.fadeOutDurationMS = fadeOutDurationMS
        self.dismissInactivityMS = dismissInactivityMS
        self.anchorToDockIcon = anchorToDockIcon
        self.bufferFromDock = bufferFromDock
        self.thumbnailCacheLifespanSec = thumbnailCacheLifespanSec
        self.thumbnailScale = thumbnailScale
        self.enableLivePreview = enableLivePreview
        self.livePreviewQuality = livePreviewQuality
        self.livePreviewFrameRate = livePreviewFrameRate
        self.liveStreamKeepAliveSec = liveStreamKeepAliveSec
        self.currentSpaceOnly = currentSpaceOnly
        self.currentMonitorOnly = currentMonitorOnly
        self.sortOrder = sortOrder
        self.includeHiddenMinimized = includeHiddenMinimized
        self.showWindowlessApps = showWindowlessApps
        self.groupAppInstances = groupAppInstances
        self.ignoreSingleWindowApps = ignoreSingleWindowApps
        self.keepPreviewOnAppQuit = keepPreviewOnAppQuit
        self.enableFolderWidget = enableFolderWidget
        self.folderShowHiddenFiles = folderShowHiddenFiles
        self.preventDockAutoHideWhileOpen = preventDockAutoHideWhileOpen
        self.skipDelayWhenPanelVisible = skipDelayWhenPanelVisible
        self.useDelayOnlyForInitialOpen = useDelayOnlyForInitialOpen
        self.preventPreviewReentryDuringFadeOut = preventPreviewReentryDuringFadeOut
        self.previewCardWidth = previewCardWidth
        self.previewCardHeight = previewCardHeight
        self.lockAspectRatio = lockAspectRatio
        self.showWindowTitle = showWindowTitle
        self.showAppNameInHeader = showAppNameInHeader
        self.compactModeThreshold = compactModeThreshold
        self.showTrafficLightButtons = showTrafficLightButtons
        self.allowDynamicImageSizing = allowDynamicImageSizing
        self.showPreviewAnimations = showPreviewAnimations
        self.previewMaxColumns = previewMaxColumns
        self.previewMaxRows = previewMaxRows
        self.globalPaddingMultiplier = globalPaddingMultiplier
        self.uniformCardRadius = uniformCardRadius
        self.enableFullSizeHoverPreview = enableFullSizeHoverPreview
        self.panelBackgroundOpacity = panelBackgroundOpacity
        self.appearanceOptions = appearanceOptions
        self.panelBackground = panelBackground
        self.hideHoverContainerBackground = hideHoverContainerBackground
        self.detachedSwitcherSearch = detachedSwitcherSearch
        self.enableWorklog = enableWorklog
        self.overlayDockTooltip = overlayDockTooltip
    }

    static let `default` = DockPreviewSettings(
        showThumbnails: true,
        hoverDelayMS: 200,          // DockDoor: 0.2s
        fadeOutDurationMS: 400,
        dismissInactivityMS: 200,
        anchorToDockIcon: true,
        bufferFromDock: -25,        // DockDoor: -25
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
        groupAppInstances: true,    // DockDoor: true
        ignoreSingleWindowApps: false,
        keepPreviewOnAppQuit: false,
        enableFolderWidget: true,   // DockDoor: true
        folderShowHiddenFiles: false,
        preventDockAutoHideWhileOpen: false,
        skipDelayWhenPanelVisible: false,
        useDelayOnlyForInitialOpen: false,
        preventPreviewReentryDuringFadeOut: false,
        previewCardWidth: 300,      // DockDoor: 300
        previewCardHeight: 188,     // DockDoor: 187.5
        lockAspectRatio: true,
        showWindowTitle: true,
        showAppNameInHeader: true,
        compactModeThreshold: 0,    // DockDoor: 0 (off by default)
        showTrafficLightButtons: true,
        allowDynamicImageSizing: false, // DockDoor: false
        showPreviewAnimations: true,
        previewMaxColumns: 2,       // DockDoor: 2
        previewMaxRows: 1,          // DockDoor: 1 (bottom dock)
        globalPaddingMultiplier: 0.7, // DockDoor: 0.7
        uniformCardRadius: true,
        enableFullSizeHoverPreview: false,
        panelBackgroundOpacity: 1.0, // DockDoor: 1.0
        appearanceOptions: .default,
        panelBackground: .default,
        hideHoverContainerBackground: false,
        detachedSwitcherSearch: false,
        enableWorklog: false,
        overlayDockTooltip: true
    )

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func decode<T: Decodable>(_ key: CodingKeys, default defaultValue: T) -> T {
            (try? container.decode(T.self, forKey: key)) ?? defaultValue
        }
        showThumbnails = decode(.showThumbnails, default: Self.default.showThumbnails)
        hoverDelayMS = decode(.hoverDelayMS, default: Self.default.hoverDelayMS)
        fadeOutDurationMS = decode(.fadeOutDurationMS, default: Self.default.fadeOutDurationMS)
        dismissInactivityMS = decode(.dismissInactivityMS, default: Self.default.dismissInactivityMS)
        anchorToDockIcon = decode(.anchorToDockIcon, default: Self.default.anchorToDockIcon)
        bufferFromDock = decode(.bufferFromDock, default: Self.default.bufferFromDock)
        thumbnailCacheLifespanSec = decode(.thumbnailCacheLifespanSec, default: Self.default.thumbnailCacheLifespanSec)
        thumbnailScale = decode(.thumbnailScale, default: Self.default.thumbnailScale)
        enableLivePreview = decode(.enableLivePreview, default: Self.default.enableLivePreview)
        livePreviewQuality = decode(.livePreviewQuality, default: Self.default.livePreviewQuality)
        livePreviewFrameRate = decode(.livePreviewFrameRate, default: Self.default.livePreviewFrameRate)
        liveStreamKeepAliveSec = decode(.liveStreamKeepAliveSec, default: Self.default.liveStreamKeepAliveSec)
        currentSpaceOnly = decode(.currentSpaceOnly, default: Self.default.currentSpaceOnly)
        currentMonitorOnly = decode(.currentMonitorOnly, default: Self.default.currentMonitorOnly)
        sortOrder = decode(.sortOrder, default: Self.default.sortOrder)
        includeHiddenMinimized = decode(.includeHiddenMinimized, default: Self.default.includeHiddenMinimized)
        showWindowlessApps = decode(.showWindowlessApps, default: Self.default.showWindowlessApps)
        groupAppInstances = decode(.groupAppInstances, default: Self.default.groupAppInstances)
        ignoreSingleWindowApps = decode(.ignoreSingleWindowApps, default: Self.default.ignoreSingleWindowApps)
        keepPreviewOnAppQuit = decode(.keepPreviewOnAppQuit, default: Self.default.keepPreviewOnAppQuit)
        enableFolderWidget = decode(.enableFolderWidget, default: Self.default.enableFolderWidget)
        folderShowHiddenFiles = decode(.folderShowHiddenFiles, default: Self.default.folderShowHiddenFiles)
        preventDockAutoHideWhileOpen = decode(.preventDockAutoHideWhileOpen, default: Self.default.preventDockAutoHideWhileOpen)
        skipDelayWhenPanelVisible = decode(.skipDelayWhenPanelVisible, default: Self.default.skipDelayWhenPanelVisible)
        useDelayOnlyForInitialOpen = decode(.useDelayOnlyForInitialOpen, default: Self.default.useDelayOnlyForInitialOpen)
        preventPreviewReentryDuringFadeOut = decode(.preventPreviewReentryDuringFadeOut, default: Self.default.preventPreviewReentryDuringFadeOut)
        previewCardWidth = decode(.previewCardWidth, default: Self.default.previewCardWidth)
        previewCardHeight = decode(.previewCardHeight, default: Self.default.previewCardHeight)
        lockAspectRatio = decode(.lockAspectRatio, default: Self.default.lockAspectRatio)
        showWindowTitle = decode(.showWindowTitle, default: Self.default.showWindowTitle)
        showAppNameInHeader = decode(.showAppNameInHeader, default: Self.default.showAppNameInHeader)
        compactModeThreshold = decode(.compactModeThreshold, default: Self.default.compactModeThreshold)
        showTrafficLightButtons = decode(.showTrafficLightButtons, default: Self.default.showTrafficLightButtons)
        allowDynamicImageSizing = decode(.allowDynamicImageSizing, default: Self.default.allowDynamicImageSizing)
        showPreviewAnimations = decode(.showPreviewAnimations, default: Self.default.showPreviewAnimations)
        previewMaxColumns = decode(.previewMaxColumns, default: Self.default.previewMaxColumns)
        previewMaxRows = decode(.previewMaxRows, default: Self.default.previewMaxRows)
        globalPaddingMultiplier = decode(.globalPaddingMultiplier, default: Self.default.globalPaddingMultiplier)
        uniformCardRadius = decode(.uniformCardRadius, default: Self.default.uniformCardRadius)
        enableFullSizeHoverPreview = decode(.enableFullSizeHoverPreview, default: Self.default.enableFullSizeHoverPreview)
        panelBackgroundOpacity = decode(.panelBackgroundOpacity, default: Self.default.panelBackgroundOpacity)
        appearanceOptions = decode(.appearanceOptions, default: .default)
        panelBackground = decode(.panelBackground, default: .default)
        hideHoverContainerBackground = decode(.hideHoverContainerBackground, default: false)
        detachedSwitcherSearch = decode(.detachedSwitcherSearch, default: false)
        enableWorklog = decode(.enableWorklog, default: Self.default.enableWorklog)
        overlayDockTooltip = decode(.overlayDockTooltip, default: Self.default.overlayDockTooltip)
    }

    var hoverDelay: TimeInterval { TimeInterval(hoverDelayMS) / 1000 }
    var fadeOutDuration: TimeInterval { TimeInterval(fadeOutDurationMS) / 1000 }
    var dismissInactivity: TimeInterval { TimeInterval(dismissInactivityMS) / 1000 }
    var thumbnailCacheLifespan: TimeInterval { TimeInterval(thumbnailCacheLifespanSec) }
}
