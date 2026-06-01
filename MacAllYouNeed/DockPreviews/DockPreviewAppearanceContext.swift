import SwiftUI

/// Resolved appearance for dock hover vs switcher vs Cmd+Tab (DockDoor `PreviewAppearanceSettings`).
struct DockPreviewAppearanceContext: Equatable {
    var showAppHeader: Bool
    var showWindowTitle: Bool
    var showTrafficLights: Bool
    var showActiveWindowBorder: Bool
    var selectionOpacity: Double
    var unselectedOpacity: Double
    var allowsFullSizeHoverPreview: Bool
    var useEmbeddedControlsOverlay: Bool
    var controlPosition: DockPreviewControlPosition
    var windowTitleVisibility: DockPreviewWindowTitleVisibility
    var trafficLightVisibility: DockPreviewTrafficLightVisibility
    var disableDockStyleTrafficLights: Bool
    var disableDockStyleTitles: Bool
    var showMinimizedHiddenLabels: Bool
    var hidePreviewCardBackground: Bool
    var previewHoverAction: DockPreviewPreviewHoverAction
    var titleOverflowStyle: DockPreviewTitleOverflowStyle
    var useMonochromeTrafficLights: Bool
    var trafficLightButtonScale: CGFloat
    var globalPaddingMultiplier: CGFloat
    var uniformCardRadius: Bool
    var showAnimations: Bool
    var activeAppIndicatorColor: Color
    var hoverHighlightColor: Color?
    var background: DockPreviewResolvedBackgroundAppearance

    static func resolve(
        mode: DockPreviewPresentationMode,
        settings: DockPreviewSettings,
        switcherShowAppHeader: Bool = false
    ) -> DockPreviewAppearanceContext {
        let options = settings.appearanceOptions
        let showHeader: Bool = switch mode {
        case .windowSwitcher: switcherShowAppHeader
        case .dockHover, .cmdTab: settings.showAppNameInHeader
        }
        let trafficLights = settings.showTrafficLightButtons
            && options.trafficLightVisibility != .never
        return DockPreviewAppearanceContext(
            showAppHeader: showHeader,
            showWindowTitle: settings.showWindowTitle,
            showTrafficLights: trafficLights,
            showActiveWindowBorder: true,
            selectionOpacity: options.selectionOpacity,
            unselectedOpacity: options.unselectedContentOpacity,
            allowsFullSizeHoverPreview: settings.enableFullSizeHoverPreview
                && options.previewHoverAction == .fullSizePreview,
            useEmbeddedControlsOverlay: options.useEmbeddedElements,
            controlPosition: options.controlPosition,
            windowTitleVisibility: options.windowTitleVisibility,
            trafficLightVisibility: options.trafficLightVisibility,
            disableDockStyleTrafficLights: options.disableDockStyleTrafficLights,
            disableDockStyleTitles: options.disableDockStyleTitles,
            showMinimizedHiddenLabels: options.showMinimizedHiddenLabels,
            hidePreviewCardBackground: options.hidePreviewCardBackground,
            previewHoverAction: options.previewHoverAction,
            titleOverflowStyle: options.titleOverflowStyle,
            useMonochromeTrafficLights: options.useMonochromeTrafficLights,
            trafficLightButtonScale: CGFloat(options.trafficLightButtonScale),
            globalPaddingMultiplier: CGFloat(settings.globalPaddingMultiplier),
            uniformCardRadius: settings.uniformCardRadius,
            showAnimations: settings.showPreviewAnimations,
            activeAppIndicatorColor: Color.accentColor,
            hoverHighlightColor: nil,
            background: DockPreviewResolvedBackgroundAppearance.resolve(options: settings.panelBackground)
        )
    }

    static func dockHover(settings: DockPreviewSettings = .default) -> DockPreviewAppearanceContext {
        resolve(mode: .dockHover, settings: settings)
    }

    static func windowSwitcher(settings: DockPreviewSettings = .default) -> DockPreviewAppearanceContext {
        resolve(mode: .windowSwitcher, settings: settings, switcherShowAppHeader: false)
    }

    static func cmdTab(settings: DockPreviewSettings = .default) -> DockPreviewAppearanceContext {
        resolve(mode: .cmdTab, settings: settings)
    }
}
