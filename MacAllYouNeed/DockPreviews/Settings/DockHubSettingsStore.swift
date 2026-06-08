import Core
import Foundation

enum DockHubSettingsStore {
    private static let settingsKey = "dockPreviews.settings"
    private static let hubKey = "dockPreviews.hub"
    private static let settingsVersionKey = "dockPreviews.settingsVersion"
    private static let currentSettingsVersion = 5  // Bump when defaults must be reset (DockDoor UI parity)

    static func load(from defaults: UserDefaults = AppGroupSettings.defaults) -> DockHubSettings {
        // Auto-reset to DockDoor-equivalent defaults when settings version is stale.
        let storedVersion = defaults.integer(forKey: settingsVersionKey)
        if storedVersion < currentSettingsVersion {
            defaults.removeObject(forKey: hubKey)
            defaults.removeObject(forKey: settingsKey)
            defaults.set(currentSettingsVersion, forKey: settingsVersionKey)
            let fresh = DockHubSettings.default
            save(fresh, to: defaults)
            return withReverseSync(fresh)
        }
        if let data = defaults.data(forKey: hubKey),
           let decoded = try? JSONDecoder().decode(DockHubSettings.self, from: data) {
            return withReverseSync(decoded)
        }
        return migrateLegacy(from: defaults)
    }

    // Populate hub.appearance.* from hub.previews.* so Customizations tab shows current values.
    private static func withReverseSync(_ hub: DockHubSettings) -> DockHubSettings {
        var h = hub
        let p = hub.previews
        let o = p.appearanceOptions

        h.appearance.showWindowTitle = p.showWindowTitle
        h.appearance.showAppName = p.showAppNameInHeader
        h.appearance.allowDynamicImageSizing = p.allowDynamicImageSizing
        h.appearance.showAnimations = p.showPreviewAnimations
        h.appearance.previewWidth = p.previewCardWidth
        h.appearance.previewHeight = p.previewCardHeight
        h.appearance.lockAspectRatio = p.lockAspectRatio
        h.appearance.previewMaxColumns = p.previewMaxColumns
        h.appearance.previewMaxRows = p.previewMaxRows
        h.appearance.globalPaddingMultiplier = p.globalPaddingMultiplier
        h.appearance.uniformCardRadius = p.uniformCardRadius
        h.appearance.hideHoverContainerBackground = p.hideHoverContainerBackground
        h.appearance.dockPreviewCompactThreshold = p.compactModeThreshold
        h.appearance.dockPreviewBackgroundOpacity = p.panelBackgroundOpacity
        h.appearance.useOpaqueBackground = p.panelBackground.useOpaqueBackground
        h.appearance.backgroundBorderOpacity = p.panelBackground.borderOpacity
        h.appearance.backgroundBorderWidth = p.panelBackground.borderWidth
        h.appearance.hoverHighlightColorHex = p.panelBackground.highlightColorHex

        h.appearance.controlPosition = o.controlPosition
        h.appearance.windowTitleVisibility = o.windowTitleVisibility == .alwaysVisible ? .alwaysVisible : .whenHoveringPreview
        h.appearance.trafficLightVisibility = reverseMapTrafficLight(o.trafficLightVisibility)
        h.appearance.useEmbeddedDockPreviewElements = o.useEmbeddedElements
        h.appearance.disableDockStyleTrafficLights = o.disableDockStyleTrafficLights
        h.appearance.disableDockStyleTitles = o.disableDockStyleTitles
        h.appearance.showMinimizedHiddenLabels = o.showMinimizedHiddenLabels
        h.appearance.enabledTrafficLightButtons = o.enabledTrafficLightButtons
        h.appearance.selectionOpacity = o.selectionOpacity
        h.appearance.unselectedContentOpacity = o.unselectedContentOpacity
        h.appearance.hidePreviewCardBackground = o.hidePreviewCardBackground
        h.appearance.titleOverflowStyle = reverseMapTitleOverflow(o.titleOverflowStyle)
        h.appearance.useMonochromeTrafficLights = o.useMonochromeTrafficLights
        h.appearance.trafficLightButtonScale = o.trafficLightButtonScale
        h.appearance.appNameStyle = mapAppNameStyleReverse(o.appNameStyle)

        h.appearance.backgroundStyle = reverseMapBackgroundStyle(p.panelBackground.style)
        h.appearance.backgroundMaterial = reverseMapBackgroundMaterial(p.panelBackground.material)

        h.switcher.maxRows = o.switcherMaxRows
        h.switcher.scrollDirection = o.switcherScrollVertical ? .vertical : .horizontal
        h.switcher.ignoreScreenLimit = o.switcherIgnoreScreenLimit

        if h.previews.thumbnailCacheLifespanSec != Int(DockAdvancedSettings.default.screenCaptureCacheLifespan) {
            h.advanced.screenCaptureCacheLifespan = Double(h.previews.thumbnailCacheLifespanSec)
        }

        h.previews.enableFolderWidget = h.widgets.enableFolderWidget
        h.previews.folderShowHiddenFiles = h.widgets.folderShowHiddenFiles

        return h
    }

    private static func reverseMapTrafficLight(_ v: DockPreviewTrafficLightVisibility) -> DockTrafficLightVisibilityMode {
        switch v {
        case .never: .never
        case .dimmedOnPreviewHover: .dimmedOnPreviewHover
        case .fullOpacityOnPreviewHover: .fullOpacityOnPreviewHover
        case .alwaysVisible: .alwaysVisible
        }
    }

    private static func reverseMapTitleOverflow(_ v: DockPreviewTitleOverflowStyle) -> DockTitleOverflowStyle {
        switch v {
        case .truncateTail: .truncateTail
        case .truncateMiddle: .truncateMiddle
        case .truncateHead: .truncateHead
        }
    }

    private static func reverseMapBackgroundStyle(_ v: DockPreviewBackgroundStyle) -> DockBackgroundStyleFull {
        switch v {
        case .liquidGlass: .liquidGlass
        case .frostedMaterial: .frostedMaterial
        case .clear: .clear
        }
    }

    private static func reverseMapBackgroundMaterial(_ v: DockPreviewBackgroundMaterial) -> DockBackgroundMaterialFull {
        switch v {
        case .hudWindow: .ultraThin
        case .sidebar: .thin
        case .menu: .regular
        case .popover: .thick
        case .titlebar: .ultraThick
        }
    }

    /// Applies appearance → previews mapping without persisting (settings mock preview).
    static func syncedForPreview(_ hub: DockHubSettings) -> DockHubSettings {
        var copy = hub
        applyAppearanceSync(&copy)
        return copy
    }

    static func save(_ settings: DockHubSettings, to defaults: UserDefaults = AppGroupSettings.defaults) {
        var synced = settings
        applyAppearanceSync(&synced)
        guard let data = try? JSONEncoder().encode(synced) else { return }
        defaults.set(data, forKey: hubKey)
        // Keep legacy blob in sync for previews-only readers.
        if let previewData = try? JSONEncoder().encode(synced.previews) {
            defaults.set(previewData, forKey: settingsKey)
        }
        NotificationCenter.default.post(name: .dockPreviewSettingsDidChange, object: nil)
        NotificationCenter.default.post(name: .dockHubSettingsDidChange, object: nil)
    }

    // Sync hub.appearance.* → hub.previews.* so the renderer picks up Customizations changes.
    private static func applyAppearanceSync(_ hub: inout DockHubSettings) {
        let a = hub.appearance

        // DockPreviewSettings direct fields
        hub.previews.showWindowTitle = a.showWindowTitle
        hub.previews.showAppNameInHeader = a.showAppName
        hub.previews.showTrafficLightButtons = a.trafficLightVisibility != .never
        hub.previews.allowDynamicImageSizing = a.allowDynamicImageSizing
        hub.previews.showPreviewAnimations = a.showAnimations
        hub.previews.previewCardWidth = a.previewWidth
        hub.previews.previewCardHeight = a.previewHeight
        hub.previews.lockAspectRatio = a.lockAspectRatio
        hub.previews.previewMaxColumns = a.previewMaxColumns
        hub.previews.previewMaxRows = a.previewMaxRows
        hub.previews.globalPaddingMultiplier = a.globalPaddingMultiplier
        hub.previews.uniformCardRadius = a.uniformCardRadius
        hub.previews.hideHoverContainerBackground = a.hideHoverContainerBackground
        hub.previews.compactModeThreshold = a.dockPreviewCompactThreshold
        hub.previews.thumbnailCacheLifespanSec = Int(hub.advanced.screenCaptureCacheLifespan.rounded())

        // AppearanceOptions fields
        hub.previews.appearanceOptions.controlPosition = a.controlPosition
        hub.previews.appearanceOptions.windowTitleVisibility = a.windowTitleVisibility == .alwaysVisible ? .alwaysVisible : .onSelection
        hub.previews.appearanceOptions.trafficLightVisibility = mapTrafficLight(a.trafficLightVisibility)
        hub.previews.appearanceOptions.useEmbeddedElements = a.useEmbeddedDockPreviewElements
        hub.previews.appearanceOptions.disableDockStyleTrafficLights = a.disableDockStyleTrafficLights
        hub.previews.appearanceOptions.disableDockStyleTitles = a.disableDockStyleTitles
        hub.previews.appearanceOptions.showMinimizedHiddenLabels = a.showMinimizedHiddenLabels
        hub.previews.appearanceOptions.enabledTrafficLightButtons = a.enabledTrafficLightButtons
        hub.previews.appearanceOptions.selectionOpacity = a.selectionOpacity
        hub.previews.appearanceOptions.unselectedContentOpacity = a.unselectedContentOpacity
        hub.previews.appearanceOptions.hidePreviewCardBackground = a.hidePreviewCardBackground
        hub.previews.appearanceOptions.titleOverflowStyle = mapTitleOverflow(a.titleOverflowStyle)
        hub.previews.appearanceOptions.useMonochromeTrafficLights = a.useMonochromeTrafficLights
        hub.previews.appearanceOptions.trafficLightButtonScale = a.trafficLightButtonScale
        hub.previews.appearanceOptions.appNameStyle = mapAppNameStyleForward(a.appNameStyle)

        // Switcher appearance → appearanceOptions
        hub.previews.appearanceOptions.switcherMaxRows = hub.switcher.maxRows
        hub.previews.appearanceOptions.switcherScrollVertical = hub.switcher.scrollDirection == .vertical
        hub.previews.appearanceOptions.switcherIgnoreScreenLimit = hub.switcher.ignoreScreenLimit

        // Panel background
        hub.previews.panelBackground.style = mapBackgroundStyle(a.backgroundStyle)
        hub.previews.panelBackground.material = mapBackgroundMaterial(a.backgroundMaterial)
        hub.previews.panelBackground.useOpaqueBackground = a.useOpaqueBackground
        hub.previews.panelBackground.borderOpacity = a.backgroundBorderOpacity
        hub.previews.panelBackground.borderWidth = a.backgroundBorderWidth
        hub.previews.panelBackground.highlightColorHex = a.hoverHighlightColorHex
        hub.previews.panelBackground.glassOpacity = a.glassOpacity
        hub.previews.panelBackground.tintOpacity = a.backgroundTintOpacity
        hub.previews.panelBackground.blurRadius = a.glassBlurRadius
        hub.previews.panelBackground.saturation = a.glassSaturation
        hub.previews.panelBackgroundOpacity = a.dockPreviewBackgroundOpacity

        // Widget sync (folder)
        hub.previews.enableFolderWidget = hub.widgets.enableFolderWidget
        hub.previews.folderShowHiddenFiles = hub.widgets.folderShowHiddenFiles
    }

    private static func mapTrafficLight(_ v: DockTrafficLightVisibilityMode) -> DockPreviewTrafficLightVisibility {
        switch v {
        case .never: .never
        case .dimmedOnPreviewHover: .dimmedOnPreviewHover
        case .fullOpacityOnPreviewHover: .fullOpacityOnPreviewHover
        case .alwaysVisible: .alwaysVisible
        }
    }

    private static func mapTitleOverflow(_ v: DockTitleOverflowStyle) -> DockPreviewTitleOverflowStyle {
        switch v {
        case .truncateTail, .marquee: .truncateTail
        case .truncateMiddle: .truncateMiddle
        case .truncateHead: .truncateHead
        }
    }

    private static func mapBackgroundStyle(_ v: DockBackgroundStyleFull) -> DockPreviewBackgroundStyle {
        switch v {
        case .liquidGlass: .liquidGlass
        case .frostedMaterial: .frostedMaterial
        case .clear: .clear
        }
    }

    private static func mapBackgroundMaterial(_ v: DockBackgroundMaterialFull) -> DockPreviewBackgroundMaterial {
        switch v {
        case .ultraThin: .hudWindow
        case .thin: .sidebar
        case .regular: .menu
        case .thick: .popover
        case .ultraThick: .titlebar
        }
    }

    private static func mapAppNameStyleForward(_ style: DockAppNameStyle) -> DockPreviewAppNameStyle {
        switch style {
        case .default: .default
        case .shadowed: .shadowed
        case .popover: .popover
        }
    }

    private static func mapAppNameStyleReverse(_ style: DockPreviewAppNameStyle) -> DockAppNameStyle {
        switch style {
        case .default: .default
        case .shadowed: .shadowed
        case .popover: .popover
        }
    }

    static func loadPreviews(from defaults: UserDefaults = AppGroupSettings.defaults) -> DockPreviewSettings {
        load(from: defaults).previews
    }

    static func savePreviews(_ previews: DockPreviewSettings, to defaults: UserDefaults = AppGroupSettings.defaults) {
        var hub = load(from: defaults)
        hub.previews = previews
        save(hub, to: defaults)
    }

    private static func migrateLegacy(from defaults: UserDefaults) -> DockHubSettings {
        var hub = DockHubSettings.default

        if let data = defaults.data(forKey: settingsKey),
           let previews = try? JSONDecoder().decode(DockPreviewSettings.self, from: data) {
            hub.previews = previews
        } else if let legacy = migrateLegacyPreviewKeysOnly(from: defaults) {
            hub.previews = legacy
        }

        if let data = defaults.data(forKey: "windowSwitcher.settings"),
           let switcher = try? JSONDecoder().decode(LegacyWindowSwitcherSettings.self, from: data) {
            hub.master.enableWindowSwitcher = switcher.enabled
            hub.switcher.shortcutKeyCode = switcher.shortcut.keyCode
            hub.switcher.shortcutModifiers = UInt32(switcher.shortcut.modifierFlags)
        }

        if defaults.object(forKey: "features.windowSwitcher.enabled") != nil {
            hub.master.enableWindowSwitcher = defaults.bool(forKey: "features.windowSwitcher.enabled")
        }
        if defaults.object(forKey: "features.cmdTabEnhancements.enabled") != nil {
            hub.master.enableCmdTabEnhancements = defaults.bool(forKey: "features.cmdTabEnhancements.enabled")
        }
        if defaults.object(forKey: "features.dockLocking.enabled") != nil {
            hub.master.enableDockLocking = defaults.bool(forKey: "features.dockLocking.enabled")
        }
        if defaults.object(forKey: "features.activeAppIndicator.enabled") != nil {
            hub.master.enableActiveAppIndicator = defaults.bool(forKey: "features.activeAppIndicator.enabled")
        }

        if let data = defaults.data(forKey: "dockLocking.settings"),
           let lock = try? JSONDecoder().decode(LegacyDockLockingSettings.self, from: data) {
            hub.master.enableDockLocking = lock.enabled
            hub.dockLock.lockedScreenIdentifier = lock.lockedScreenIdentifier
        }

        if let data = defaults.data(forKey: "activeAppIndicator.settings"),
           let indicator = try? JSONDecoder().decode(LegacyActiveAppIndicatorSettings.self, from: data) {
            hub.master.enableActiveAppIndicator = indicator.enabled
            hub.indicator.colorHex = indicator.colorHex
            hub.indicator.height = indicator.height
            hub.indicator.offset = indicator.offset
        }

        hub.previews.enableFolderWidget = hub.widgets.enableFolderWidget
        hub.previews.folderShowHiddenFiles = hub.widgets.folderShowHiddenFiles

        save(hub, to: defaults)
        return hub
    }

    private static func migrateLegacyPreviewKeysOnly(from defaults: UserDefaults) -> DockPreviewSettings? {
        var settings = DockPreviewSettings.default
        var migrated = false
        if defaults.object(forKey: "dockPreviews.showThumbnails") != nil {
            settings.showThumbnails = defaults.bool(forKey: "dockPreviews.showThumbnails")
            migrated = true
        }
        if defaults.object(forKey: "dockPreviews.hoverDelayMS") != nil {
            settings.hoverDelayMS = defaults.integer(forKey: "dockPreviews.hoverDelayMS")
            migrated = true
        }
        return migrated ? settings : nil
    }
}

private struct LegacyDockLockingSettings: Codable {
    var enabled: Bool
    var lockedScreenIdentifier: String?
}

private struct LegacyActiveAppIndicatorSettings: Codable {
    var enabled: Bool
    var colorHex: String
    var height: Double
    var offset: Double
}

private struct LegacyWindowSwitcherSettings: Codable {
    struct Shortcut: Codable {
        var keyCode: UInt16
        var modifierFlags: UInt
    }

    var enabled: Bool
    var shortcut: Shortcut
}

extension Notification.Name {
    static let dockHubSettingsDidChange = Notification.Name("dockHubSettingsDidChange")
    static let dockPreviewSettingsDidChange = Notification.Name("dockPreviewSettingsDidChange")
}
