import Carbon.HIToolbox
import Foundation

// MARK: - Master toggles

struct DockHubMasterSettings: Codable, Equatable {
    var enableDockPreviews: Bool
    var enableWindowSwitcher: Bool
    var enableCmdTabEnhancements: Bool
    var enableDockLocking: Bool
    var enableActiveAppIndicator: Bool

    static let `default` = DockHubMasterSettings(
        enableDockPreviews: true,
        enableWindowSwitcher: true,
        enableCmdTabEnhancements: false,
        enableDockLocking: false,
        enableActiveAppIndicator: false
    )
}

// MARK: - Window switcher

struct DockSwitcherSettings: Equatable {
    var shortcutKeyCode: UInt16
    var shortcutModifiers: UInt32
    var instantSwitcher: Bool
    var preventSwitcherHide: Bool
    var enableSearch: Bool
    var focusSearchOnOpen: Bool
    var searchFuzziness: Int
    var searchTriggerKeyCode: UInt16
    var useClassicWindowOrdering: Bool
    var enableMouseHover: Bool
    var mouseHoverAutoScrollSpeed: Double
    var currentSpaceOnly: Bool
    var currentMonitorOnly: Bool
    var limitToFrontmostApp: Bool
    var includeHiddenWindows: Bool
    var showWindowlessApps: Bool
    var sortOrder: DockSortOrder
    var groupedApps: [String]
    var placementStrategy: DockSwitcherPlacementStrategy
    var pinnedScreenIdentifier: String?
    var enableOffsetPlacement: Bool
    var anchorToTop: Bool
    var horizontalOffsetPercent: Double
    var verticalOffsetPercent: Double
    var mouseFollowsFocus: DockSwitcherMouseFollowsFocus
    var showAppHeader: Bool
    var appIconSize: Double
    var scrollDirection: DockSwitcherScrollDirection
    var maxRows: Int
    var ignoreScreenLimit: Bool
    var controlPosition: DockPreviewControlPosition
    var trafficLightVisibility: DockTrafficLightVisibilityMode
    var enabledTrafficLightButtons: Set<DockPreviewWindowAction>
    var useMonochromeTrafficLights: Bool
    var disableDockStyleTrafficLights: Bool
    var showWindowTitle: Bool
    var windowTitleVisibility: DockWindowTitleVisibilityMode
    var useEmbeddedElements: Bool
    var alternateShortcutKeyCode: UInt16
    var alternateShortcutModifiers: UInt32
    var alternateShortcutMode: DockSwitcherInvocationMode
    var backwardKeyCode: UInt16
    var selectionKeyCode: UInt16
    var requireShiftToGoBack: Bool
    var enableVimMotions: Bool
    var passArrowsThrough: Bool
    var fullscreenAppBlacklist: [String]
    var compactThreshold: Int
    var previewAtOriginalPosition: Bool
    var stickyWindowSwitching: Bool
    var switcherLayoutStyle: DockSwitcherLayoutStyle
    var cursorAutoCenterOnFocus: Bool
    var excludesAutoCenterBundleIDs: [String]

    static let `default` = DockSwitcherSettings(
        shortcutKeyCode: 48,
        shortcutModifiers: UInt32(optionKey),
        instantSwitcher: false,
        preventSwitcherHide: false,
        enableSearch: false,
        focusSearchOnOpen: false,
        searchFuzziness: 3,
        searchTriggerKeyCode: 44,
        useClassicWindowOrdering: true,
        enableMouseHover: false,
        mouseHoverAutoScrollSpeed: 4.0,
        currentSpaceOnly: false,
        currentMonitorOnly: false,
        limitToFrontmostApp: false,
        includeHiddenWindows: true,
        showWindowlessApps: true,
        sortOrder: .recentlyUsed,
        groupedApps: [],
        placementStrategy: .screenWithMouse,
        pinnedScreenIdentifier: nil,
        enableOffsetPlacement: false,
        anchorToTop: false,
        horizontalOffsetPercent: 0,
        verticalOffsetPercent: 0,
        mouseFollowsFocus: .never,
        showAppHeader: true,
        appIconSize: 0,
        scrollDirection: .horizontal,
        maxRows: 8,
        ignoreScreenLimit: false,
        controlPosition: .topTrailing,
        trafficLightVisibility: .dimmedOnPreviewHover,
        enabledTrafficLightButtons: [.quit, .close, .minimize, .toggleFullScreen],
        useMonochromeTrafficLights: false,
        disableDockStyleTrafficLights: false,
        showWindowTitle: true,
        windowTitleVisibility: .alwaysVisible,
        useEmbeddedElements: false,
        alternateShortcutKeyCode: 0,
        alternateShortcutModifiers: 0,
        alternateShortcutMode: .activeAppOnly,
        backwardKeyCode: 56,
        selectionKeyCode: 36,
        requireShiftToGoBack: false,
        enableVimMotions: false,
        passArrowsThrough: false,
        fullscreenAppBlacklist: [],
        compactThreshold: 0,
        previewAtOriginalPosition: false,
        stickyWindowSwitching: false,
        switcherLayoutStyle: .horizontalGrid,
        cursorAutoCenterOnFocus: false,
        excludesAutoCenterBundleIDs: []
    )
}

extension DockSwitcherSettings: Codable {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func d<T: Decodable>(_ key: CodingKeys, _ def: T) -> T { (try? c.decode(T.self, forKey: key)) ?? def }
        let s = DockSwitcherSettings.default
        shortcutKeyCode = d(.shortcutKeyCode, s.shortcutKeyCode)
        shortcutModifiers = d(.shortcutModifiers, s.shortcutModifiers)
        instantSwitcher = d(.instantSwitcher, s.instantSwitcher)
        preventSwitcherHide = d(.preventSwitcherHide, s.preventSwitcherHide)
        enableSearch = d(.enableSearch, s.enableSearch)
        focusSearchOnOpen = d(.focusSearchOnOpen, s.focusSearchOnOpen)
        searchFuzziness = d(.searchFuzziness, s.searchFuzziness)
        searchTriggerKeyCode = d(.searchTriggerKeyCode, s.searchTriggerKeyCode)
        useClassicWindowOrdering = d(.useClassicWindowOrdering, s.useClassicWindowOrdering)
        enableMouseHover = d(.enableMouseHover, s.enableMouseHover)
        mouseHoverAutoScrollSpeed = d(.mouseHoverAutoScrollSpeed, s.mouseHoverAutoScrollSpeed)
        currentSpaceOnly = d(.currentSpaceOnly, s.currentSpaceOnly)
        currentMonitorOnly = d(.currentMonitorOnly, s.currentMonitorOnly)
        limitToFrontmostApp = d(.limitToFrontmostApp, s.limitToFrontmostApp)
        includeHiddenWindows = d(.includeHiddenWindows, s.includeHiddenWindows)
        showWindowlessApps = d(.showWindowlessApps, s.showWindowlessApps)
        sortOrder = d(.sortOrder, s.sortOrder)
        groupedApps = d(.groupedApps, s.groupedApps)
        placementStrategy = d(.placementStrategy, s.placementStrategy)
        pinnedScreenIdentifier = d(.pinnedScreenIdentifier, s.pinnedScreenIdentifier)
        enableOffsetPlacement = d(.enableOffsetPlacement, s.enableOffsetPlacement)
        anchorToTop = d(.anchorToTop, s.anchorToTop)
        horizontalOffsetPercent = d(.horizontalOffsetPercent, s.horizontalOffsetPercent)
        verticalOffsetPercent = d(.verticalOffsetPercent, s.verticalOffsetPercent)
        mouseFollowsFocus = d(.mouseFollowsFocus, s.mouseFollowsFocus)
        showAppHeader = d(.showAppHeader, s.showAppHeader)
        appIconSize = d(.appIconSize, s.appIconSize)
        scrollDirection = d(.scrollDirection, s.scrollDirection)
        maxRows = d(.maxRows, s.maxRows)
        ignoreScreenLimit = d(.ignoreScreenLimit, s.ignoreScreenLimit)
        controlPosition = d(.controlPosition, s.controlPosition)
        trafficLightVisibility = d(.trafficLightVisibility, s.trafficLightVisibility)
        enabledTrafficLightButtons = d(.enabledTrafficLightButtons, s.enabledTrafficLightButtons)
        useMonochromeTrafficLights = d(.useMonochromeTrafficLights, s.useMonochromeTrafficLights)
        disableDockStyleTrafficLights = d(.disableDockStyleTrafficLights, s.disableDockStyleTrafficLights)
        showWindowTitle = d(.showWindowTitle, s.showWindowTitle)
        windowTitleVisibility = d(.windowTitleVisibility, s.windowTitleVisibility)
        useEmbeddedElements = d(.useEmbeddedElements, s.useEmbeddedElements)
        alternateShortcutKeyCode = d(.alternateShortcutKeyCode, s.alternateShortcutKeyCode)
        alternateShortcutModifiers = d(.alternateShortcutModifiers, s.alternateShortcutModifiers)
        alternateShortcutMode = d(.alternateShortcutMode, s.alternateShortcutMode)
        backwardKeyCode = d(.backwardKeyCode, s.backwardKeyCode)
        selectionKeyCode = d(.selectionKeyCode, s.selectionKeyCode)
        requireShiftToGoBack = d(.requireShiftToGoBack, s.requireShiftToGoBack)
        enableVimMotions = d(.enableVimMotions, s.enableVimMotions)
        passArrowsThrough = d(.passArrowsThrough, s.passArrowsThrough)
        fullscreenAppBlacklist = d(.fullscreenAppBlacklist, s.fullscreenAppBlacklist)
        compactThreshold = d(.compactThreshold, s.compactThreshold)
        previewAtOriginalPosition = d(.previewAtOriginalPosition, s.previewAtOriginalPosition)
        stickyWindowSwitching = d(.stickyWindowSwitching, s.stickyWindowSwitching)
        switcherLayoutStyle = d(.switcherLayoutStyle, s.switcherLayoutStyle)
        cursorAutoCenterOnFocus = d(.cursorAutoCenterOnFocus, s.cursorAutoCenterOnFocus)
        excludesAutoCenterBundleIDs = d(.excludesAutoCenterBundleIDs, s.excludesAutoCenterBundleIDs)
    }
}

// MARK: - Cmd+Tab

struct DockCmdTabSettings: Equatable {
    var autoSelectFirstWindow: Bool
    var cycleKeyCode: UInt16
    var backwardCycleKeyCode: UInt16
    var currentSpaceOnly: Bool
    var currentMonitorOnly: Bool
    var includeHiddenWindows: Bool
    var showWindowlessApps: Bool
    var ignoreAppsWithSingleWindow: Bool
    var sortOrder: DockSortOrder
    var showAppName: Bool
    var appNameStyle: DockCmdTabAppNameStyle
    var showAppIconOnly: Bool
    var showWindowTitle: Bool
    var windowTitleVisibility: DockWindowTitleVisibilityMode
    var windowTitlePosition: DockWindowTitlePosition
    var disableDockStyleTitles: Bool
    var controlPosition: DockPreviewControlPosition
    var trafficLightVisibility: DockTrafficLightVisibilityMode
    var trafficLightPosition: DockTrafficLightPosition
    var enabledTrafficLightButtons: Set<DockPreviewWindowAction>
    var useMonochromeTrafficLights: Bool
    var disableDockStyleTrafficLights: Bool
    var useEmbeddedElements: Bool
    var compactThreshold: Int
    var hasSeenFocusHint: Bool

    static let `default` = DockCmdTabSettings(
        autoSelectFirstWindow: false,
        cycleKeyCode: 0,
        backwardCycleKeyCode: 50,
        currentSpaceOnly: false,
        currentMonitorOnly: false,
        includeHiddenWindows: true,
        showWindowlessApps: false,
        ignoreAppsWithSingleWindow: false,
        sortOrder: .recentlyUsed,
        showAppName: true,
        appNameStyle: .default,
        showAppIconOnly: false,
        showWindowTitle: true,
        windowTitleVisibility: .alwaysVisible,
        windowTitlePosition: .bottomLeft,
        disableDockStyleTitles: false,
        controlPosition: .topTrailing,
        trafficLightVisibility: .dimmedOnPreviewHover,
        trafficLightPosition: .topLeft,
        enabledTrafficLightButtons: [.quit, .close, .minimize, .toggleFullScreen],
        useMonochromeTrafficLights: false,
        disableDockStyleTrafficLights: false,
        useEmbeddedElements: false,
        compactThreshold: 0,
        hasSeenFocusHint: false
    )
}

extension DockCmdTabSettings: Codable {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func d<T: Decodable>(_ key: CodingKeys, _ def: T) -> T { (try? c.decode(T.self, forKey: key)) ?? def }
        let s = DockCmdTabSettings.default
        autoSelectFirstWindow = d(.autoSelectFirstWindow, s.autoSelectFirstWindow)
        cycleKeyCode = d(.cycleKeyCode, s.cycleKeyCode)
        backwardCycleKeyCode = d(.backwardCycleKeyCode, s.backwardCycleKeyCode)
        currentSpaceOnly = d(.currentSpaceOnly, s.currentSpaceOnly)
        currentMonitorOnly = d(.currentMonitorOnly, s.currentMonitorOnly)
        includeHiddenWindows = d(.includeHiddenWindows, s.includeHiddenWindows)
        showWindowlessApps = d(.showWindowlessApps, s.showWindowlessApps)
        ignoreAppsWithSingleWindow = d(.ignoreAppsWithSingleWindow, s.ignoreAppsWithSingleWindow)
        sortOrder = d(.sortOrder, s.sortOrder)
        showAppName = d(.showAppName, s.showAppName)
        appNameStyle = d(.appNameStyle, s.appNameStyle)
        showAppIconOnly = d(.showAppIconOnly, s.showAppIconOnly)
        showWindowTitle = d(.showWindowTitle, s.showWindowTitle)
        windowTitleVisibility = d(.windowTitleVisibility, s.windowTitleVisibility)
        windowTitlePosition = d(.windowTitlePosition, s.windowTitlePosition)
        disableDockStyleTitles = d(.disableDockStyleTitles, s.disableDockStyleTitles)
        controlPosition = d(.controlPosition, s.controlPosition)
        trafficLightVisibility = d(.trafficLightVisibility, s.trafficLightVisibility)
        trafficLightPosition = d(.trafficLightPosition, s.trafficLightPosition)
        enabledTrafficLightButtons = d(.enabledTrafficLightButtons, s.enabledTrafficLightButtons)
        useMonochromeTrafficLights = d(.useMonochromeTrafficLights, s.useMonochromeTrafficLights)
        disableDockStyleTrafficLights = d(.disableDockStyleTrafficLights, s.disableDockStyleTrafficLights)
        useEmbeddedElements = d(.useEmbeddedElements, s.useEmbeddedElements)
        compactThreshold = d(.compactThreshold, s.compactThreshold)
        hasSeenFocusHint = d(.hasSeenFocusHint, s.hasSeenFocusHint)
    }
}

// MARK: - Dock lock

enum DockLockOverrideModifier: String, Codable, CaseIterable, Identifiable {
    case option, control, shift, command
    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

struct DockLockSettings: Codable, Equatable {
    var lockedScreenIdentifier: String?
    var overrideModifier: DockLockOverrideModifier

    static let `default` = DockLockSettings(
        lockedScreenIdentifier: nil,
        overrideModifier: .option
    )
}

// MARK: - Active indicator

struct DockIndicatorSettings: Equatable {
    var colorHex: String
    var autoSize: Bool
    var autoLength: Bool
    var height: Double
    var offset: Double
    var length: Double
    var shift: Double

    static let `default` = DockIndicatorSettings(
        colorHex: "#007AFF",
        autoSize: true,
        autoLength: false,
        height: 4,   // DockDoor: 4.0
        offset: 5,   // DockDoor: 5.0
        length: 40,
        shift: 0
    )
}

extension DockIndicatorSettings: Codable {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func d<T: Decodable>(_ key: CodingKeys, _ def: T) -> T { (try? c.decode(T.self, forKey: key)) ?? def }
        let s = DockIndicatorSettings.default
        colorHex = d(.colorHex, s.colorHex)
        autoSize = d(.autoSize, s.autoSize)
        autoLength = d(.autoLength, s.autoLength)
        height = d(.height, s.height)
        offset = d(.offset, s.offset)
        length = d(.length, s.length)
        shift = d(.shift, s.shift)
    }
}

// MARK: - Widgets

struct DockWidgetSettings: Equatable {
    var enableMediaWidget: Bool
    var enableCalendarWidget: Bool
    var enableFolderWidget: Bool
    var folderShowHiddenFiles: Bool
    var enableDockItemWidgets: Bool
    var showSpecialAppControls: Bool
    var mediaDetectionMode: DockMediaDetectionMode
    var useEmbeddedMediaControls: Bool
    var showBigControlsWhenNoValidWindows: Bool
    var enablePinning: Bool
    var folderSortOrder: DockFolderSortOrder
    var folderSortReversed: Bool
    var folderRememberSortPerFolder: Bool
    /// Per-folder sort order overrides (`path` → `DockFolderSortOrder.rawValue`).
    var folderSortOrders: [String: String]
    /// Per-folder reverse-sort overrides.
    var folderSortReversedByPath: [String: Bool]
    var filteredCalendarIdentifiers: [String]

    static let `default` = DockWidgetSettings(
        enableMediaWidget: true,
        enableCalendarWidget: true,
        enableFolderWidget: true,
        folderShowHiddenFiles: false,
        enableDockItemWidgets: true,
        showSpecialAppControls: true,
        mediaDetectionMode: .universal,
        useEmbeddedMediaControls: true,
        showBigControlsWhenNoValidWindows: true,
        enablePinning: true,
        folderSortOrder: .dateModified,
        folderSortReversed: true,
        folderRememberSortPerFolder: true,
        folderSortOrders: [:],
        folderSortReversedByPath: [:],
        filteredCalendarIdentifiers: []
    )
}

extension DockWidgetSettings: Codable {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func d<T: Decodable>(_ key: CodingKeys, _ def: T) -> T { (try? c.decode(T.self, forKey: key)) ?? def }
        let s = DockWidgetSettings.default
        enableMediaWidget = d(.enableMediaWidget, s.enableMediaWidget)
        enableCalendarWidget = d(.enableCalendarWidget, s.enableCalendarWidget)
        enableFolderWidget = d(.enableFolderWidget, s.enableFolderWidget)
        folderShowHiddenFiles = d(.folderShowHiddenFiles, s.folderShowHiddenFiles)
        enableDockItemWidgets = d(.enableDockItemWidgets, s.enableDockItemWidgets)
        showSpecialAppControls = d(.showSpecialAppControls, s.showSpecialAppControls)
        mediaDetectionMode = d(.mediaDetectionMode, s.mediaDetectionMode)
        useEmbeddedMediaControls = d(.useEmbeddedMediaControls, s.useEmbeddedMediaControls)
        showBigControlsWhenNoValidWindows = d(.showBigControlsWhenNoValidWindows, s.showBigControlsWhenNoValidWindows)
        enablePinning = d(.enablePinning, s.enablePinning)
        folderSortOrder = d(.folderSortOrder, s.folderSortOrder)
        folderSortReversed = d(.folderSortReversed, s.folderSortReversed)
        folderRememberSortPerFolder = d(.folderRememberSortPerFolder, s.folderRememberSortPerFolder)
        folderSortOrders = d(.folderSortOrders, s.folderSortOrders)
        folderSortReversedByPath = d(.folderSortReversedByPath, s.folderSortReversedByPath)
        filteredCalendarIdentifiers = d(.filteredCalendarIdentifiers, s.filteredCalendarIdentifiers)
    }
}

// MARK: - Gesture settings

struct DockGestureSettingsFull: Equatable {
    var enableDockScrollGesture: Bool
    var dockScrollBehavior: DockScrollGestureBehavior
    var dockScrollMediaBehavior: DockScrollGestureMediaBehavior
    var enableTitleBarScrollGesture: Bool
    var titleBarSizingMode: DockTitleBarSizingMode
    var titleBarCenteredScale: Double
    var titleBarCenteredWidthScale: Double
    var titleBarCenteredHeightScale: Double
    var titleBarLockAspectRatio: Bool
    var titleBarRestoreInterval: Double
    var enableDockPreviewGestures: Bool
    var swipeTowardsDockAction: DockWindowSwipeAction
    var swipeAwayFromDockAction: DockWindowSwipeAction
    var aeroShakeAction: DockAeroShakeAction
    var enableSwitcherGestures: Bool
    var switcherSwipeUpAction: DockWindowSwipeAction
    var switcherSwipeDownAction: DockWindowSwipeAction
    var gestureSwipeThreshold: Double
    var middleClickAction: DockMiddleClickAction
    var cmdShortcut1Key: UInt16
    var cmdShortcut1Action: DockWindowSwipeAction
    var cmdShortcut2Key: UInt16
    var cmdShortcut2Action: DockWindowSwipeAction
    var cmdShortcut3Key: UInt16
    var cmdShortcut3Action: DockWindowSwipeAction
    var mediaScrollBehavior: DockMediaScrollBehavior
    var mediaScrollDirection: DockMediaScrollDirection

    static let `default` = DockGestureSettingsFull(
        enableDockScrollGesture: false,
        dockScrollBehavior: .activateHide,
        dockScrollMediaBehavior: .adjustVolume,
        enableTitleBarScrollGesture: false,
        titleBarSizingMode: .uniform,
        titleBarCenteredScale: 0.8,
        titleBarCenteredWidthScale: 0.8,
        titleBarCenteredHeightScale: 0.8,
        titleBarLockAspectRatio: false,
        titleBarRestoreInterval: 1.5,
        enableDockPreviewGestures: true,  // DockDoor: true
        swipeTowardsDockAction: .minimize,
        swipeAwayFromDockAction: .maximize,
        aeroShakeAction: .none,
        enableSwitcherGestures: true,     // DockDoor: true
        switcherSwipeUpAction: .maximize,
        switcherSwipeDownAction: .minimize,
        gestureSwipeThreshold: 50,
        middleClickAction: .close,
        cmdShortcut1Key: 13,
        cmdShortcut1Action: .close,
        cmdShortcut2Key: 46,
        cmdShortcut2Action: .minimize,
        cmdShortcut3Key: 12,
        cmdShortcut3Action: .quit,
        mediaScrollBehavior: .seekPlayback,
        mediaScrollDirection: .vertical
    )
}

extension DockGestureSettingsFull: Codable {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func d<T: Decodable>(_ key: CodingKeys, _ def: T) -> T { (try? c.decode(T.self, forKey: key)) ?? def }
        let s = DockGestureSettingsFull.default
        enableDockScrollGesture = d(.enableDockScrollGesture, s.enableDockScrollGesture)
        dockScrollBehavior = d(.dockScrollBehavior, s.dockScrollBehavior)
        dockScrollMediaBehavior = d(.dockScrollMediaBehavior, s.dockScrollMediaBehavior)
        enableTitleBarScrollGesture = d(.enableTitleBarScrollGesture, s.enableTitleBarScrollGesture)
        titleBarSizingMode = d(.titleBarSizingMode, s.titleBarSizingMode)
        titleBarCenteredScale = d(.titleBarCenteredScale, s.titleBarCenteredScale)
        titleBarCenteredWidthScale = d(.titleBarCenteredWidthScale, s.titleBarCenteredWidthScale)
        titleBarCenteredHeightScale = d(.titleBarCenteredHeightScale, s.titleBarCenteredHeightScale)
        titleBarLockAspectRatio = d(.titleBarLockAspectRatio, s.titleBarLockAspectRatio)
        titleBarRestoreInterval = d(.titleBarRestoreInterval, s.titleBarRestoreInterval)
        enableDockPreviewGestures = d(.enableDockPreviewGestures, s.enableDockPreviewGestures)
        swipeTowardsDockAction = d(.swipeTowardsDockAction, s.swipeTowardsDockAction)
        swipeAwayFromDockAction = d(.swipeAwayFromDockAction, s.swipeAwayFromDockAction)
        aeroShakeAction = d(.aeroShakeAction, s.aeroShakeAction)
        enableSwitcherGestures = d(.enableSwitcherGestures, s.enableSwitcherGestures)
        switcherSwipeUpAction = d(.switcherSwipeUpAction, s.switcherSwipeUpAction)
        switcherSwipeDownAction = d(.switcherSwipeDownAction, s.switcherSwipeDownAction)
        gestureSwipeThreshold = d(.gestureSwipeThreshold, s.gestureSwipeThreshold)
        middleClickAction = d(.middleClickAction, s.middleClickAction)
        cmdShortcut1Key = d(.cmdShortcut1Key, s.cmdShortcut1Key)
        cmdShortcut1Action = d(.cmdShortcut1Action, s.cmdShortcut1Action)
        cmdShortcut2Key = d(.cmdShortcut2Key, s.cmdShortcut2Key)
        cmdShortcut2Action = d(.cmdShortcut2Action, s.cmdShortcut2Action)
        cmdShortcut3Key = d(.cmdShortcut3Key, s.cmdShortcut3Key)
        cmdShortcut3Action = d(.cmdShortcut3Action, s.cmdShortcut3Action)
        mediaScrollBehavior = d(.mediaScrollBehavior, s.mediaScrollBehavior)
        mediaScrollDirection = d(.mediaScrollDirection, s.mediaScrollDirection)
    }
}

// MARK: - Appearance settings (full)

struct DockAppearanceSettingsFull: Equatable {
    var backgroundStyle: DockBackgroundStyleFull
    var backgroundMaterial: DockBackgroundMaterialFull
    var glassOpacity: Double
    var glassBlurRadius: Double
    var glassSaturation: Double
    var backgroundTintOpacity: Double
    var backgroundBorderOpacity: Double
    var backgroundBorderWidth: Double
    var useOpaqueBackground: Bool
    var customBackgroundColorHex: String?
    var hoverHighlightColorHex: String?
    var dockPreviewBackgroundOpacity: Double
    var appAppearanceMode: DockAppearanceMode
    var globalPaddingMultiplier: Double
    var uniformCardRadius: Bool
    var showAnimations: Bool
    var selectionOpacity: Double
    var unselectedContentOpacity: Double
    var titleOverflowStyle: DockTitleOverflowStyle
    var showMinimizedHiddenLabels: Bool
    var showWindowlessAppQuitButton: Bool
    var hidePreviewCardBackground: Bool
    var hideHoverContainerBackground: Bool
    var hideWidgetContainerBackground: Bool
    var showActiveWindowBorder: Bool
    var lockAspectRatio: Bool
    var allowDynamicImageSizing: Bool
    var previewWidth: Int
    var previewHeight: Int
    var showAppName: Bool
    var appNameStyle: DockAppNameStyle
    var showAppIconOnly: Bool
    var controlPosition: DockPreviewControlPosition
    var showWindowTitle: Bool
    var windowTitleVisibility: DockWindowTitleVisibilityMode
    var windowTitleDisplayCondition: DockWindowTitleDisplayCondition
    var windowTitleFontSize: DockWindowTitleFontSize
    var windowTitlePosition: DockWindowTitlePosition
    var disableDockStyleTitles: Bool
    var trafficLightVisibility: DockTrafficLightVisibilityMode
    var trafficLightPosition: DockTrafficLightPosition
    var enabledTrafficLightButtons: Set<DockPreviewWindowAction>
    var useMonochromeTrafficLights: Bool
    var trafficLightButtonScale: Double
    var disableDockStyleTrafficLights: Bool
    var showMassActionButtons: Bool
    var useEmbeddedDockPreviewElements: Bool
    var previewMaxRows: Int
    var previewMaxColumns: Int
    var disableImagePreview: Bool
    var compactModeItemSize: DockCompactModeItemSize
    var compactModeTitleFormat: DockCompactModeTitleFormat
    var compactModeHideTrafficLights: Bool
    var dockPreviewCompactThreshold: Int
    var windowSwitcherCompactThreshold: Int
    var cmdTabCompactThreshold: Int

    static let `default` = DockAppearanceSettingsFull(
        backgroundStyle: .liquidGlass,
        backgroundMaterial: .ultraThin,
        glassOpacity: 0.95,
        glassBlurRadius: 0,
        glassSaturation: 1.0,
        backgroundTintOpacity: 0.3,
        backgroundBorderOpacity: 0.15,
        backgroundBorderWidth: 1.0,
        useOpaqueBackground: false,
        customBackgroundColorHex: nil,
        hoverHighlightColorHex: nil,
        dockPreviewBackgroundOpacity: 1.0,
        appAppearanceMode: .system,
        globalPaddingMultiplier: 0.7,    // DockDoor: 0.7
        uniformCardRadius: true,
        showAnimations: true,
        selectionOpacity: 0.4,
        unselectedContentOpacity: 0.75,
        titleOverflowStyle: .truncateMiddle, // DockDoor: truncateMiddle
        showMinimizedHiddenLabels: true,
        showWindowlessAppQuitButton: false,
        hidePreviewCardBackground: false,
        hideHoverContainerBackground: false,
        hideWidgetContainerBackground: false,
        showActiveWindowBorder: false,
        lockAspectRatio: true,
        allowDynamicImageSizing: false,  // DockDoor: false
        previewWidth: 300,               // DockDoor: 300
        previewHeight: 188,              // DockDoor: 187.5
        showAppName: true,
        appNameStyle: .default,
        showAppIconOnly: false,
        controlPosition: .topTrailing,
        showWindowTitle: true,
        windowTitleVisibility: .alwaysVisible,
        windowTitleDisplayCondition: .all,
        windowTitleFontSize: .system,
        windowTitlePosition: .bottomLeft,
        disableDockStyleTitles: false,
        trafficLightVisibility: .dimmedOnPreviewHover,
        trafficLightPosition: .topLeft,
        enabledTrafficLightButtons: [.quit, .close, .minimize, .toggleFullScreen],
        useMonochromeTrafficLights: false,
        trafficLightButtonScale: 1.0,
        disableDockStyleTrafficLights: false,
        showMassActionButtons: true,
        useEmbeddedDockPreviewElements: false,
        previewMaxRows: 1,               // DockDoor: 1 (bottom dock)
        previewMaxColumns: 2,            // DockDoor: 2
        disableImagePreview: false,
        compactModeItemSize: .medium,
        compactModeTitleFormat: .appNameAndTitle,
        compactModeHideTrafficLights: false,
        dockPreviewCompactThreshold: 0,  // DockDoor: 0
        windowSwitcherCompactThreshold: 0,
        cmdTabCompactThreshold: 0
    )
}

extension DockAppearanceSettingsFull: Codable {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func d<T: Decodable>(_ key: CodingKeys, _ def: T) -> T { (try? c.decode(T.self, forKey: key)) ?? def }
        let s = DockAppearanceSettingsFull.default
        backgroundStyle = d(.backgroundStyle, s.backgroundStyle)
        backgroundMaterial = d(.backgroundMaterial, s.backgroundMaterial)
        glassOpacity = d(.glassOpacity, s.glassOpacity)
        glassBlurRadius = d(.glassBlurRadius, s.glassBlurRadius)
        glassSaturation = d(.glassSaturation, s.glassSaturation)
        backgroundTintOpacity = d(.backgroundTintOpacity, s.backgroundTintOpacity)
        backgroundBorderOpacity = d(.backgroundBorderOpacity, s.backgroundBorderOpacity)
        backgroundBorderWidth = d(.backgroundBorderWidth, s.backgroundBorderWidth)
        useOpaqueBackground = d(.useOpaqueBackground, s.useOpaqueBackground)
        customBackgroundColorHex = d(.customBackgroundColorHex, s.customBackgroundColorHex)
        hoverHighlightColorHex = d(.hoverHighlightColorHex, s.hoverHighlightColorHex)
        dockPreviewBackgroundOpacity = d(.dockPreviewBackgroundOpacity, s.dockPreviewBackgroundOpacity)
        appAppearanceMode = d(.appAppearanceMode, s.appAppearanceMode)
        globalPaddingMultiplier = d(.globalPaddingMultiplier, s.globalPaddingMultiplier)
        uniformCardRadius = d(.uniformCardRadius, s.uniformCardRadius)
        showAnimations = d(.showAnimations, s.showAnimations)
        selectionOpacity = d(.selectionOpacity, s.selectionOpacity)
        unselectedContentOpacity = d(.unselectedContentOpacity, s.unselectedContentOpacity)
        titleOverflowStyle = d(.titleOverflowStyle, s.titleOverflowStyle)
        showMinimizedHiddenLabels = d(.showMinimizedHiddenLabels, s.showMinimizedHiddenLabels)
        showWindowlessAppQuitButton = d(.showWindowlessAppQuitButton, s.showWindowlessAppQuitButton)
        hidePreviewCardBackground = d(.hidePreviewCardBackground, s.hidePreviewCardBackground)
        hideHoverContainerBackground = d(.hideHoverContainerBackground, s.hideHoverContainerBackground)
        hideWidgetContainerBackground = d(.hideWidgetContainerBackground, s.hideWidgetContainerBackground)
        showActiveWindowBorder = d(.showActiveWindowBorder, s.showActiveWindowBorder)
        lockAspectRatio = d(.lockAspectRatio, s.lockAspectRatio)
        allowDynamicImageSizing = d(.allowDynamicImageSizing, s.allowDynamicImageSizing)
        previewWidth = d(.previewWidth, s.previewWidth)
        previewHeight = d(.previewHeight, s.previewHeight)
        showAppName = d(.showAppName, s.showAppName)
        appNameStyle = d(.appNameStyle, s.appNameStyle)
        showAppIconOnly = d(.showAppIconOnly, s.showAppIconOnly)
        controlPosition = d(.controlPosition, s.controlPosition)
        showWindowTitle = d(.showWindowTitle, s.showWindowTitle)
        windowTitleVisibility = d(.windowTitleVisibility, s.windowTitleVisibility)
        windowTitleDisplayCondition = d(.windowTitleDisplayCondition, s.windowTitleDisplayCondition)
        windowTitleFontSize = d(.windowTitleFontSize, s.windowTitleFontSize)
        windowTitlePosition = d(.windowTitlePosition, s.windowTitlePosition)
        disableDockStyleTitles = d(.disableDockStyleTitles, s.disableDockStyleTitles)
        trafficLightVisibility = d(.trafficLightVisibility, s.trafficLightVisibility)
        trafficLightPosition = d(.trafficLightPosition, s.trafficLightPosition)
        enabledTrafficLightButtons = d(.enabledTrafficLightButtons, s.enabledTrafficLightButtons)
        useMonochromeTrafficLights = d(.useMonochromeTrafficLights, s.useMonochromeTrafficLights)
        trafficLightButtonScale = d(.trafficLightButtonScale, s.trafficLightButtonScale)
        disableDockStyleTrafficLights = d(.disableDockStyleTrafficLights, s.disableDockStyleTrafficLights)
        showMassActionButtons = d(.showMassActionButtons, s.showMassActionButtons)
        useEmbeddedDockPreviewElements = d(.useEmbeddedDockPreviewElements, s.useEmbeddedDockPreviewElements)
        previewMaxRows = d(.previewMaxRows, s.previewMaxRows)
        previewMaxColumns = d(.previewMaxColumns, s.previewMaxColumns)
        disableImagePreview = d(.disableImagePreview, s.disableImagePreview)
        compactModeItemSize = d(.compactModeItemSize, s.compactModeItemSize)
        compactModeTitleFormat = d(.compactModeTitleFormat, s.compactModeTitleFormat)
        compactModeHideTrafficLights = d(.compactModeHideTrafficLights, s.compactModeHideTrafficLights)
        dockPreviewCompactThreshold = d(.dockPreviewCompactThreshold, s.dockPreviewCompactThreshold)
        windowSwitcherCompactThreshold = d(.windowSwitcherCompactThreshold, s.windowSwitcherCompactThreshold)
        cmdTabCompactThreshold = d(.cmdTabCompactThreshold, s.cmdTabCompactThreshold)
    }
}

// MARK: - Advanced settings

struct DockAdvancedSettings: Equatable {
    var windowProcessingDebounceMS: Int
    var raisedWindowLevel: Bool
    var disableImagePreview: Bool
    var debugMode: Bool
    var windowImageCaptureQuality: DockWindowImageCaptureQuality
    var screenCaptureCacheLifespan: Double
    var windowPreviewImageScale: Int
    var enableLivePreviewForDock: Bool
    var dockLivePreviewQuality: DockLivePreviewQuality
    var dockLivePreviewFrameRate: DockLivePreviewFrameRate
    var enableLivePreviewForSwitcher: Bool
    var switcherLivePreviewQuality: DockLivePreviewQuality
    var switcherLivePreviewFrameRate: DockLivePreviewFrameRate
    var switcherLivePreviewScope: DockLivePreviewScope
    var livePreviewStreamKeepAlive: Int
    var disableMinWindowSizeFilter: Bool
    var openNewWindowForWindowlessApps: Bool

    static let `default` = DockAdvancedSettings(
        windowProcessingDebounceMS: 300,
        raisedWindowLevel: true,
        disableImagePreview: false,
        debugMode: false,
        windowImageCaptureQuality: .nominal,
        screenCaptureCacheLifespan: 60,
        windowPreviewImageScale: 1,
        enableLivePreviewForDock: false,
        dockLivePreviewQuality: .high,
        dockLivePreviewFrameRate: .fps24,
        enableLivePreviewForSwitcher: false,
        switcherLivePreviewQuality: .low,
        switcherLivePreviewFrameRate: .fps10,
        switcherLivePreviewScope: .selectedAppWindows,
        livePreviewStreamKeepAlive: 0,
        disableMinWindowSizeFilter: false,
        openNewWindowForWindowlessApps: false
    )
}

extension DockAdvancedSettings: Codable {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func d<T: Decodable>(_ key: CodingKeys, _ def: T) -> T { (try? c.decode(T.self, forKey: key)) ?? def }
        let s = DockAdvancedSettings.default
        windowProcessingDebounceMS = d(.windowProcessingDebounceMS, s.windowProcessingDebounceMS)
        raisedWindowLevel = d(.raisedWindowLevel, s.raisedWindowLevel)
        disableImagePreview = d(.disableImagePreview, s.disableImagePreview)
        debugMode = d(.debugMode, s.debugMode)
        windowImageCaptureQuality = d(.windowImageCaptureQuality, s.windowImageCaptureQuality)
        screenCaptureCacheLifespan = d(.screenCaptureCacheLifespan, s.screenCaptureCacheLifespan)
        windowPreviewImageScale = d(.windowPreviewImageScale, s.windowPreviewImageScale)
        enableLivePreviewForDock = d(.enableLivePreviewForDock, s.enableLivePreviewForDock)
        dockLivePreviewQuality = d(.dockLivePreviewQuality, s.dockLivePreviewQuality)
        dockLivePreviewFrameRate = d(.dockLivePreviewFrameRate, s.dockLivePreviewFrameRate)
        enableLivePreviewForSwitcher = d(.enableLivePreviewForSwitcher, s.enableLivePreviewForSwitcher)
        switcherLivePreviewQuality = d(.switcherLivePreviewQuality, s.switcherLivePreviewQuality)
        switcherLivePreviewFrameRate = d(.switcherLivePreviewFrameRate, s.switcherLivePreviewFrameRate)
        switcherLivePreviewScope = d(.switcherLivePreviewScope, s.switcherLivePreviewScope)
        livePreviewStreamKeepAlive = d(.livePreviewStreamKeepAlive, s.livePreviewStreamKeepAlive)
        disableMinWindowSizeFilter = d(.disableMinWindowSizeFilter, s.disableMinWindowSizeFilter)
        openNewWindowForWindowlessApps = d(.openNewWindowForWindowlessApps, s.openNewWindowForWindowlessApps)
    }
}

// MARK: - Filter settings

struct DockFilterSettings: Equatable {
    var appNameFilters: [String]
    var windowTitleFilters: [String]
    var widgetAppFilters: [String]
    var groupedAppsInSwitcher: [String]
    var fullscreenAppBlacklist: [String]
    var sortMinimizedToEnd: Bool
    var customAppDirectories: [String]

    static let `default` = DockFilterSettings(
        appNameFilters: [],
        windowTitleFilters: [],
        widgetAppFilters: [],
        groupedAppsInSwitcher: [],
        fullscreenAppBlacklist: [],
        sortMinimizedToEnd: false,
        customAppDirectories: []
    )
}

extension DockFilterSettings: Codable {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func d<T: Decodable>(_ key: CodingKeys, _ def: T) -> T { (try? c.decode(T.self, forKey: key)) ?? def }
        let s = DockFilterSettings.default
        appNameFilters = d(.appNameFilters, s.appNameFilters)
        windowTitleFilters = d(.windowTitleFilters, s.windowTitleFilters)
        widgetAppFilters = d(.widgetAppFilters, s.widgetAppFilters)
        groupedAppsInSwitcher = d(.groupedAppsInSwitcher, s.groupedAppsInSwitcher)
        fullscreenAppBlacklist = d(.fullscreenAppBlacklist, s.fullscreenAppBlacklist)
        sortMinimizedToEnd = d(.sortMinimizedToEnd, s.sortMinimizedToEnd)
        customAppDirectories = d(.customAppDirectories, s.customAppDirectories)
    }
}

// MARK: - Dock interaction settings

struct DockInteractionSettings: Equatable {
    var enableCmdRightClickQuit: Bool
    var quitAppOnLastWindowClose: Bool
    var hideAllOnDockClick: Bool
    var dockClickAction: DockClickAction
    var restoreAllMinimizedOnDockClick: Bool

    static let `default` = DockInteractionSettings(
        enableCmdRightClickQuit: true,
        quitAppOnLastWindowClose: false,
        hideAllOnDockClick: false,
        dockClickAction: .hide,
        restoreAllMinimizedOnDockClick: true
    )
}

extension DockInteractionSettings: Codable {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func d<T: Decodable>(_ key: CodingKeys, _ def: T) -> T { (try? c.decode(T.self, forKey: key)) ?? def }
        let s = DockInteractionSettings.default
        enableCmdRightClickQuit = d(.enableCmdRightClickQuit, s.enableCmdRightClickQuit)
        quitAppOnLastWindowClose = d(.quitAppOnLastWindowClose, s.quitAppOnLastWindowClose)
        hideAllOnDockClick = d(.hideAllOnDockClick, s.hideAllOnDockClick)
        dockClickAction = d(.dockClickAction, s.dockClickAction)
        restoreAllMinimizedOnDockClick = d(.restoreAllMinimizedOnDockClick, s.restoreAllMinimizedOnDockClick)
    }
}

// MARK: - Hub root

struct DockHubSettings: Equatable {
    var master: DockHubMasterSettings
    var previews: DockPreviewSettings
    var switcher: DockSwitcherSettings
    var cmdTab: DockCmdTabSettings
    var dockLock: DockLockSettings
    var indicator: DockIndicatorSettings
    var widgets: DockWidgetSettings
    var gestures: DockGestureSettingsFull
    var appearance: DockAppearanceSettingsFull
    var advanced: DockAdvancedSettings
    var filters: DockFilterSettings
    var interaction: DockInteractionSettings

    static let `default` = DockHubSettings(
        master: .default,
        previews: .default,
        switcher: .default,
        cmdTab: .default,
        dockLock: .default,
        indicator: .default,
        widgets: .default,
        gestures: .default,
        appearance: .default,
        advanced: .default,
        filters: .default,
        interaction: .default
    )
}

extension DockHubSettings: Codable {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func d<T: Decodable>(_ key: CodingKeys, _ def: T) -> T { (try? c.decode(T.self, forKey: key)) ?? def }
        master = d(.master, .default)
        previews = d(.previews, .default)
        switcher = d(.switcher, .default)
        cmdTab = d(.cmdTab, .default)
        dockLock = d(.dockLock, .default)
        indicator = d(.indicator, .default)
        widgets = d(.widgets, .default)
        gestures = d(.gestures, .default)
        appearance = d(.appearance, .default)
        advanced = d(.advanced, .default)
        filters = d(.filters, .default)
        interaction = d(.interaction, .default)
    }
}
