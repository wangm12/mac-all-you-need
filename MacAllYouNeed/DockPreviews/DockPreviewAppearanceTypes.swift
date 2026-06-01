import SwiftUI

// MARK: - Background (DockDoor `BackgroundAppearance` subset)

enum DockPreviewBackgroundStyle: String, Codable, CaseIterable {
    case frostedMaterial
    case clear
}

enum DockPreviewBackgroundMaterial: String, Codable, CaseIterable {
    case hudWindow
    case sidebar
    case menu
    case popover
    case titlebar

    var nsMaterial: NSVisualEffectView.Material {
        switch self {
        case .hudWindow: .hudWindow
        case .sidebar: .sidebar
        case .menu: .menu
        case .popover: .popover
        case .titlebar: .titlebar
        }
    }
}

// MARK: - Card chrome (DockDoor `PreviewAppearanceSettings` subset)

enum DockPreviewControlPosition: String, Codable, CaseIterable {
    case embeddedBottom
    case embeddedTop
    case centeredControlsBottomTitleTop
    case centeredTitleBottomControlsTop
    case diagonalTopLeftBottomRight
    case diagonalTopRightBottomLeft
    case diagonalBottomLeftTopRight
    case diagonalBottomRightTopLeft
    case parallelTopLeftBottomLeft
    case parallelTopRightBottomRight
    case parallelBottomLeftTopLeft
    case parallelBottomRightTopRight

    var isCentered: Bool {
        switch self {
        case .centeredControlsBottomTitleTop, .centeredTitleBottomControlsTop: true
        default: false
        }
    }

    var showsOnTop: Bool {
        switch self {
        case .embeddedTop,
             .centeredTitleBottomControlsTop, .centeredControlsBottomTitleTop,
             .diagonalTopLeftBottomRight, .diagonalTopRightBottomLeft,
             .parallelTopLeftBottomLeft, .parallelTopRightBottomRight: true
        default: false
        }
    }

    var showsOnBottom: Bool {
        switch self {
        case .embeddedBottom,
             .centeredControlsBottomTitleTop, .centeredTitleBottomControlsTop,
             .diagonalBottomLeftTopRight, .diagonalBottomRightTopLeft,
             .parallelBottomLeftTopLeft, .parallelBottomRightTopRight: true
        default: false
        }
    }

    struct SlotConfiguration {
        var showTitle: Bool
        var showControls: Bool
        var isLeadingControls: Bool
    }

    var topConfiguration: SlotConfiguration {
        slotConfig(forTop: true)
    }

    var bottomConfiguration: SlotConfiguration {
        slotConfig(forTop: false)
    }

    private func slotConfig(forTop: Bool) -> SlotConfiguration {
        switch self {
        case .embeddedTop:
            return SlotConfiguration(showTitle: true, showControls: true, isLeadingControls: true)
        case .embeddedBottom:
            return SlotConfiguration(showTitle: true, showControls: true, isLeadingControls: true)
        case .centeredControlsBottomTitleTop:
            return forTop
                ? SlotConfiguration(showTitle: true, showControls: false, isLeadingControls: false)
                : SlotConfiguration(showTitle: false, showControls: true, isLeadingControls: false)
        case .centeredTitleBottomControlsTop:
            return forTop
                ? SlotConfiguration(showTitle: false, showControls: true, isLeadingControls: false)
                : SlotConfiguration(showTitle: true, showControls: false, isLeadingControls: false)
        case .diagonalTopLeftBottomRight:
            return forTop
                ? SlotConfiguration(showTitle: true, showControls: false, isLeadingControls: true)
                : SlotConfiguration(showTitle: false, showControls: true, isLeadingControls: false)
        case .diagonalTopRightBottomLeft:
            return forTop
                ? SlotConfiguration(showTitle: true, showControls: false, isLeadingControls: false)
                : SlotConfiguration(showTitle: false, showControls: true, isLeadingControls: true)
        case .diagonalBottomLeftTopRight:
            return forTop
                ? SlotConfiguration(showTitle: false, showControls: true, isLeadingControls: false)
                : SlotConfiguration(showTitle: true, showControls: false, isLeadingControls: true)
        case .diagonalBottomRightTopLeft:
            return forTop
                ? SlotConfiguration(showTitle: false, showControls: true, isLeadingControls: true)
                : SlotConfiguration(showTitle: true, showControls: false, isLeadingControls: false)
        case .parallelTopLeftBottomLeft:
            return SlotConfiguration(showTitle: true, showControls: true, isLeadingControls: true)
        case .parallelTopRightBottomRight:
            return SlotConfiguration(showTitle: true, showControls: true, isLeadingControls: false)
        case .parallelBottomLeftTopLeft:
            return forTop
                ? SlotConfiguration(showTitle: false, showControls: true, isLeadingControls: true)
                : SlotConfiguration(showTitle: true, showControls: false, isLeadingControls: true)
        case .parallelBottomRightTopRight:
            return forTop
                ? SlotConfiguration(showTitle: false, showControls: true, isLeadingControls: false)
                : SlotConfiguration(showTitle: true, showControls: false, isLeadingControls: false)
        }
    }
}

enum DockPreviewWindowTitleVisibility: String, Codable, CaseIterable {
    case alwaysVisible
    case onSelection
}

enum DockPreviewTrafficLightVisibility: String, Codable, CaseIterable {
    case never
    case onHover
    case always
}

enum DockPreviewTitleOverflowStyle: String, Codable, CaseIterable {
    case truncateTail
    case truncateMiddle
    case truncateHead
}

enum DockPreviewPreviewHoverAction: String, Codable, CaseIterable {
    case none
    case fullSizePreview
}

struct DockPreviewAppearanceOptions: Codable, Equatable {
    var controlPosition: DockPreviewControlPosition
    var windowTitleVisibility: DockPreviewWindowTitleVisibility
    var trafficLightVisibility: DockPreviewTrafficLightVisibility
    var useEmbeddedElements: Bool
    var disableDockStyleTrafficLights: Bool
    var disableDockStyleTitles: Bool
    var showMinimizedHiddenLabels: Bool
    var selectionOpacity: Double
    var unselectedContentOpacity: Double
    var hidePreviewCardBackground: Bool
    var previewHoverAction: DockPreviewPreviewHoverAction
    var titleOverflowStyle: DockPreviewTitleOverflowStyle
    var useMonochromeTrafficLights: Bool
    var trafficLightButtonScale: Double
    var switcherMaxRows: Int
    var switcherScrollVertical: Bool
    var switcherIgnoreScreenLimit: Bool

    static let `default` = DockPreviewAppearanceOptions(
        controlPosition: .embeddedBottom,
        windowTitleVisibility: .onSelection,
        trafficLightVisibility: .onHover,
        useEmbeddedElements: true,
        disableDockStyleTrafficLights: false,
        disableDockStyleTitles: false,
        showMinimizedHiddenLabels: true,
        selectionOpacity: 0.4,
        unselectedContentOpacity: 0.75,
        hidePreviewCardBackground: false,
        previewHoverAction: .none,
        titleOverflowStyle: .truncateTail,
        useMonochromeTrafficLights: false,
        trafficLightButtonScale: 1.0,
        switcherMaxRows: 3,
        switcherScrollVertical: false,
        switcherIgnoreScreenLimit: false
    )
}

struct DockPreviewPanelBackgroundOptions: Codable, Equatable {
    var style: DockPreviewBackgroundStyle
    var material: DockPreviewBackgroundMaterial
    var borderOpacity: Double
    var borderWidth: Double
    var useOpaqueBackground: Bool
    var highlightColorHex: String?

    static let `default` = DockPreviewPanelBackgroundOptions(
        style: .frostedMaterial,
        material: .hudWindow,
        borderOpacity: 0.22,
        borderWidth: 0.5,
        useOpaqueBackground: false,
        highlightColorHex: nil
    )
}
