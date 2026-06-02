import AppKit
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
    var enabledTrafficLightButtons: Set<DockPreviewWindowAction>
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
    var showMassActionButtons: Bool
    var background: DockPreviewResolvedBackgroundAppearance
    var windowTitleFont: Font         // DockDoor `windowTitleFontSize.font`
    var appNameStyle: DockPreviewAppNameStyle

    static func resolve(
        mode: DockPreviewPresentationMode,
        settings: DockPreviewSettings,
        hubAppearance: DockAppearanceSettingsFull = .default,
        switcherShowAppHeader: Bool = false
    ) -> DockPreviewAppearanceContext {
        let options = settings.appearanceOptions
        let showHeader: Bool = switch mode {
        case .windowSwitcher: switcherShowAppHeader
        case .dockHover, .cmdTab: settings.showAppNameInHeader
        }
        let trafficLights = settings.showTrafficLightButtons
            && options.trafficLightVisibility != .never
        let highlight = colorFromHex(hubAppearance.hoverHighlightColorHex)
        let indicatorColor = colorFromHex(hubAppearance.hoverHighlightColorHex) ?? Color.accentColor
        return DockPreviewAppearanceContext(
            showAppHeader: showHeader,
            showWindowTitle: settings.showWindowTitle,
            showTrafficLights: trafficLights,
            showActiveWindowBorder: hubAppearance.showActiveWindowBorder,
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
            enabledTrafficLightButtons: options.enabledTrafficLightButtons,
            hidePreviewCardBackground: options.hidePreviewCardBackground,
            previewHoverAction: options.previewHoverAction,
            titleOverflowStyle: options.titleOverflowStyle,
            useMonochromeTrafficLights: options.useMonochromeTrafficLights,
            trafficLightButtonScale: CGFloat(options.trafficLightButtonScale),
            globalPaddingMultiplier: CGFloat(settings.globalPaddingMultiplier),
            uniformCardRadius: settings.uniformCardRadius,
            showAnimations: settings.showPreviewAnimations,
            activeAppIndicatorColor: indicatorColor,
            hoverHighlightColor: highlight,
            showMassActionButtons: hubAppearance.showMassActionButtons,
            background: DockPreviewResolvedBackgroundAppearance.resolve(options: settings.panelBackground),
            windowTitleFont: hubAppearance.windowTitleFontSize.font,
            appNameStyle: mapAppNameStyle(hubAppearance.appNameStyle)
        )
    }

    private static func mapAppNameStyle(_ style: DockAppNameStyle) -> DockPreviewAppNameStyle {
        switch style {
        case .default: .default
        case .shadowed: .shadowed
        case .popover: .popover
        }
    }

    private static func colorFromHex(_ hex: String?) -> Color? {
        guard var cleaned = hex?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        if cleaned.hasPrefix("#") { cleaned.removeFirst() }
        guard cleaned.count == 6, let value = UInt32(cleaned, radix: 16) else { return nil }
        let r = CGFloat((value >> 16) & 0xFF) / 255
        let g = CGFloat((value >> 8) & 0xFF) / 255
        let b = CGFloat(value & 0xFF) / 255
        return Color(nsColor: NSColor(srgbRed: r, green: g, blue: b, alpha: 1))
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
