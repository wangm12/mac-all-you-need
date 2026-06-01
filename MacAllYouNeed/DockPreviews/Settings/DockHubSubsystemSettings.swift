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

struct DockSwitcherSettings: Codable, Equatable {
    var shortcutKeyCode: UInt16
    var shortcutModifiers: UInt32
    var instantSwitcher: Bool
    var enableSearch: Bool
    var currentSpaceOnly: Bool
    var currentMonitorOnly: Bool
    var includeHiddenWindows: Bool
    var showWindowlessApps: Bool
    var compactThreshold: Int
    var placementUsesMouseScreen: Bool

    static let `default` = DockSwitcherSettings(
        shortcutKeyCode: 48,
        shortcutModifiers: UInt32(optionKey),
        instantSwitcher: false,
        enableSearch: false,
        currentSpaceOnly: false,
        currentMonitorOnly: false,
        includeHiddenWindows: true,
        showWindowlessApps: true,
        compactThreshold: 0,
        placementUsesMouseScreen: true
    )
}

// MARK: - Cmd+Tab

struct DockCmdTabSettings: Codable, Equatable {
    var autoSelectFirstWindow: Bool
    var cycleKeyCode: UInt16
    var backwardCycleKeyCode: UInt16
    var currentSpaceOnly: Bool
    var currentMonitorOnly: Bool
    var includeHiddenWindows: Bool
    var showWindowlessApps: Bool
    var compactThreshold: Int

    static let `default` = DockCmdTabSettings(
        autoSelectFirstWindow: false,
        cycleKeyCode: 0,
        backwardCycleKeyCode: 50,
        currentSpaceOnly: false,
        currentMonitorOnly: false,
        includeHiddenWindows: true,
        showWindowlessApps: false,
        compactThreshold: 0
    )
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

struct DockIndicatorSettings: Codable, Equatable {
    var colorHex: String
    var autoSize: Bool
    var height: Double
    var offset: Double
    var length: Double

    static let `default` = DockIndicatorSettings(
        colorHex: "#007AFF",
        autoSize: true,
        height: 3,
        offset: 0,
        length: 0
    )
}

// MARK: - Widgets

struct DockWidgetSettings: Codable, Equatable {
    var enableMediaWidget: Bool
    var enableCalendarWidget: Bool
    var enableFolderWidget: Bool
    var folderShowHiddenFiles: Bool

    static let `default` = DockWidgetSettings(
        enableMediaWidget: true,
        enableCalendarWidget: true,
        enableFolderWidget: false,
        folderShowHiddenFiles: false
    )
}

// MARK: - Gestures (fixed behaviors only)

struct DockGestureSettings: Codable, Equatable {
    var enableDockScrollOnIcon: Bool
    var enableTitleBarScroll: Bool
    var enablePreviewTrackpadGestures: Bool
    var enableSwitcherTrackpadGestures: Bool
    var swipeThreshold: Double

    static let `default` = DockGestureSettings(
        enableDockScrollOnIcon: false,
        enableTitleBarScroll: false,
        enablePreviewTrackpadGestures: false,
        enableSwitcherTrackpadGestures: false,
        swipeThreshold: 12
    )
}

// MARK: - Appearance

struct DockAppearanceSettings: Codable, Equatable {
    var selectionOpacity: Double
    var unselectedOpacity: Double
    var hideContainerBackground: Bool
    var useOpaqueBackground: Bool
    var showAnimations: Bool

    static let `default` = DockAppearanceSettings(
        selectionOpacity: 0.4,
        unselectedOpacity: 0.75,
        hideContainerBackground: false,
        useOpaqueBackground: false,
        showAnimations: true
    )
}

// MARK: - Advanced

struct DockAdvancedSettings: Codable, Equatable {
    var windowProcessingDebounceMS: Int
    var raisedWindowLevel: Bool
    var disableImagePreview: Bool
    var debugMode: Bool

    static let `default` = DockAdvancedSettings(
        windowProcessingDebounceMS: 300,
        raisedWindowLevel: true,
        disableImagePreview: false,
        debugMode: false
    )
}

// MARK: - Hub root

struct DockHubSettings: Codable, Equatable {
    var master: DockHubMasterSettings
    var previews: DockPreviewSettings
    var switcher: DockSwitcherSettings
    var cmdTab: DockCmdTabSettings
    var dockLock: DockLockSettings
    var indicator: DockIndicatorSettings
    var widgets: DockWidgetSettings
    var gestures: DockGestureSettings
    var appearance: DockAppearanceSettings
    var advanced: DockAdvancedSettings

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
        advanced: .default
    )
}
