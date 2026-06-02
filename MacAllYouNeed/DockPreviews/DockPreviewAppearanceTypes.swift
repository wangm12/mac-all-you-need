import SwiftUI

// MARK: - Background (DockDoor `BackgroundAppearance` subset)

enum DockPreviewBackgroundStyle: String, Codable, CaseIterable {
    case liquidGlass
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

    var swiftUIMaterial: Material {
        switch self {
        case .hudWindow: .ultraThinMaterial
        case .sidebar: .thinMaterial
        case .menu: .regularMaterial
        case .popover: .thickMaterial
        case .titlebar: .ultraThickMaterial
        }
    }
}

// MARK: - Card chrome (DockDoor `PreviewAppearanceSettings` subset)

enum DockPreviewControlPosition: String, Codable, CaseIterable {
    case topLeading
    case topTrailing
    case bottomLeading
    case bottomTrailing
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
        case .topLeading, .topTrailing,
             .embeddedTop,
             .centeredTitleBottomControlsTop, .centeredControlsBottomTitleTop,
             .diagonalTopLeftBottomRight, .diagonalTopRightBottomLeft,
             .parallelTopLeftBottomLeft, .parallelTopRightBottomRight: true
        default: false
        }
    }

    var showsOnBottom: Bool {
        switch self {
        case .bottomLeading, .bottomTrailing,
             .embeddedBottom,
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
        case .topLeading, .bottomLeading:
            return SlotConfiguration(showTitle: true, showControls: true, isLeadingControls: false)
        case .topTrailing, .bottomTrailing:
            return SlotConfiguration(showTitle: true, showControls: true, isLeadingControls: true)
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
            return forTop
                ? SlotConfiguration(showTitle: true, showControls: false, isLeadingControls: true)
                : SlotConfiguration(showTitle: false, showControls: true, isLeadingControls: true)
        case .parallelTopRightBottomRight:
            return forTop
                ? SlotConfiguration(showTitle: true, showControls: false, isLeadingControls: false)
                : SlotConfiguration(showTitle: false, showControls: true, isLeadingControls: false)
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

enum DockPreviewTrafficLightVisibility: String, Codable, CaseIterable, Identifiable {
    case never
    case dimmedOnPreviewHover
    case fullOpacityOnPreviewHover
    case alwaysVisible

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .never: "Never visible"
        case .dimmedOnPreviewHover: "On hover; dimmed until button hover"
        case .fullOpacityOnPreviewHover: "On hover; full opacity"
        case .alwaysVisible: "Always visible"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        switch raw {
        case "onHover": self = .fullOpacityOnPreviewHover
        case "always": self = .alwaysVisible
        default:
            self = Self(rawValue: raw) ?? .dimmedOnPreviewHover
        }
    }
}

enum DockPreviewAppNameStyle: String, Codable, CaseIterable {
    case `default`
    case shadowed
    case popover

    var displayName: String {
        switch self {
        case .default: "Default"
        case .shadowed: "Shadowed"
        case .popover: "Popover"
        }
    }
}

enum DockPreviewTitleOverflowStyle: String, Codable, CaseIterable {
    case truncateTail
    case truncateMiddle
    case truncateHead
}

enum DockPreviewPreviewHoverAction: String, Codable, CaseIterable {
    case none
    case fullSizePreview

    var displayName: String {
        switch self {
        case .none: "None"
        case .fullSizePreview: "Full-size preview"
        }
    }
}

struct DockPreviewAppearanceOptions: Codable, Equatable {
    var controlPosition: DockPreviewControlPosition
    var windowTitleVisibility: DockPreviewWindowTitleVisibility
    var trafficLightVisibility: DockPreviewTrafficLightVisibility
    var useEmbeddedElements: Bool
    var disableDockStyleTrafficLights: Bool
    var disableDockStyleTitles: Bool
    var showMinimizedHiddenLabels: Bool
    var enabledTrafficLightButtons: Set<DockPreviewWindowAction>
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
    var appNameStyle: DockPreviewAppNameStyle

    init(
        controlPosition: DockPreviewControlPosition,
        windowTitleVisibility: DockPreviewWindowTitleVisibility,
        trafficLightVisibility: DockPreviewTrafficLightVisibility,
        useEmbeddedElements: Bool,
        disableDockStyleTrafficLights: Bool,
        disableDockStyleTitles: Bool,
        showMinimizedHiddenLabels: Bool,
        enabledTrafficLightButtons: Set<DockPreviewWindowAction>,
        selectionOpacity: Double,
        unselectedContentOpacity: Double,
        hidePreviewCardBackground: Bool,
        previewHoverAction: DockPreviewPreviewHoverAction,
        titleOverflowStyle: DockPreviewTitleOverflowStyle,
        useMonochromeTrafficLights: Bool,
        trafficLightButtonScale: Double,
        switcherMaxRows: Int,
        switcherScrollVertical: Bool,
        switcherIgnoreScreenLimit: Bool,
        appNameStyle: DockPreviewAppNameStyle = .default
    ) {
        self.controlPosition = controlPosition
        self.windowTitleVisibility = windowTitleVisibility
        self.trafficLightVisibility = trafficLightVisibility
        self.useEmbeddedElements = useEmbeddedElements
        self.disableDockStyleTrafficLights = disableDockStyleTrafficLights
        self.disableDockStyleTitles = disableDockStyleTitles
        self.showMinimizedHiddenLabels = showMinimizedHiddenLabels
        self.enabledTrafficLightButtons = enabledTrafficLightButtons
        self.selectionOpacity = selectionOpacity
        self.unselectedContentOpacity = unselectedContentOpacity
        self.hidePreviewCardBackground = hidePreviewCardBackground
        self.previewHoverAction = previewHoverAction
        self.titleOverflowStyle = titleOverflowStyle
        self.useMonochromeTrafficLights = useMonochromeTrafficLights
        self.trafficLightButtonScale = trafficLightButtonScale
        self.switcherMaxRows = switcherMaxRows
        self.switcherScrollVertical = switcherScrollVertical
        self.switcherIgnoreScreenLimit = switcherIgnoreScreenLimit
        self.appNameStyle = appNameStyle
    }

    static let `default` = DockPreviewAppearanceOptions(
        controlPosition: .topTrailing,
        windowTitleVisibility: .alwaysVisible,
        trafficLightVisibility: .dimmedOnPreviewHover,
        useEmbeddedElements: false,
        disableDockStyleTrafficLights: false,
        disableDockStyleTitles: false,
        showMinimizedHiddenLabels: true,
        enabledTrafficLightButtons: [.quit, .close, .minimize, .toggleFullScreen],
        selectionOpacity: 0.4,
        unselectedContentOpacity: 0.75,
        hidePreviewCardBackground: false,
        previewHoverAction: .none,
        titleOverflowStyle: .truncateMiddle, // DockDoor default
        useMonochromeTrafficLights: false,
        trafficLightButtonScale: 1.0,
        switcherMaxRows: 8,
        switcherScrollVertical: false, // horizontal layout for dock preview
        switcherIgnoreScreenLimit: false
    )

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func decode<T: Decodable>(_ key: CodingKeys, default defaultValue: T) -> T {
            (try? container.decode(T.self, forKey: key)) ?? defaultValue
        }
        controlPosition = decode(.controlPosition, default: Self.default.controlPosition)
        switch controlPosition {
        case .embeddedBottom: controlPosition = .bottomTrailing
        case .embeddedTop: controlPosition = .topTrailing
        default: break
        }
        windowTitleVisibility = decode(.windowTitleVisibility, default: Self.default.windowTitleVisibility)
        trafficLightVisibility = decode(.trafficLightVisibility, default: Self.default.trafficLightVisibility)
        useEmbeddedElements = decode(.useEmbeddedElements, default: Self.default.useEmbeddedElements)
        if useEmbeddedElements {
            useEmbeddedElements = false
        }
        if windowTitleVisibility == .onSelection {
            windowTitleVisibility = .alwaysVisible
        }
        disableDockStyleTrafficLights = decode(.disableDockStyleTrafficLights, default: Self.default.disableDockStyleTrafficLights)
        disableDockStyleTitles = decode(.disableDockStyleTitles, default: Self.default.disableDockStyleTitles)
        showMinimizedHiddenLabels = decode(.showMinimizedHiddenLabels, default: Self.default.showMinimizedHiddenLabels)
        enabledTrafficLightButtons = decode(.enabledTrafficLightButtons, default: Self.default.enabledTrafficLightButtons)
        selectionOpacity = decode(.selectionOpacity, default: Self.default.selectionOpacity)
        unselectedContentOpacity = decode(.unselectedContentOpacity, default: Self.default.unselectedContentOpacity)
        hidePreviewCardBackground = decode(.hidePreviewCardBackground, default: Self.default.hidePreviewCardBackground)
        previewHoverAction = decode(.previewHoverAction, default: Self.default.previewHoverAction)
        titleOverflowStyle = decode(.titleOverflowStyle, default: Self.default.titleOverflowStyle)
        useMonochromeTrafficLights = decode(.useMonochromeTrafficLights, default: Self.default.useMonochromeTrafficLights)
        trafficLightButtonScale = decode(.trafficLightButtonScale, default: Self.default.trafficLightButtonScale)
        switcherMaxRows = decode(.switcherMaxRows, default: Self.default.switcherMaxRows)
        switcherScrollVertical = decode(.switcherScrollVertical, default: Self.default.switcherScrollVertical)
        switcherIgnoreScreenLimit = decode(.switcherIgnoreScreenLimit, default: Self.default.switcherIgnoreScreenLimit)
        appNameStyle = decode(.appNameStyle, default: Self.default.appNameStyle)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(controlPosition, forKey: .controlPosition)
        try container.encode(windowTitleVisibility, forKey: .windowTitleVisibility)
        try container.encode(trafficLightVisibility, forKey: .trafficLightVisibility)
        try container.encode(useEmbeddedElements, forKey: .useEmbeddedElements)
        try container.encode(disableDockStyleTrafficLights, forKey: .disableDockStyleTrafficLights)
        try container.encode(disableDockStyleTitles, forKey: .disableDockStyleTitles)
        try container.encode(showMinimizedHiddenLabels, forKey: .showMinimizedHiddenLabels)
        try container.encode(enabledTrafficLightButtons, forKey: .enabledTrafficLightButtons)
        try container.encode(selectionOpacity, forKey: .selectionOpacity)
        try container.encode(unselectedContentOpacity, forKey: .unselectedContentOpacity)
        try container.encode(hidePreviewCardBackground, forKey: .hidePreviewCardBackground)
        try container.encode(previewHoverAction, forKey: .previewHoverAction)
        try container.encode(titleOverflowStyle, forKey: .titleOverflowStyle)
        try container.encode(useMonochromeTrafficLights, forKey: .useMonochromeTrafficLights)
        try container.encode(trafficLightButtonScale, forKey: .trafficLightButtonScale)
        try container.encode(switcherMaxRows, forKey: .switcherMaxRows)
        try container.encode(switcherScrollVertical, forKey: .switcherScrollVertical)
        try container.encode(switcherIgnoreScreenLimit, forKey: .switcherIgnoreScreenLimit)
        try container.encode(appNameStyle, forKey: .appNameStyle)
    }

    private enum CodingKeys: String, CodingKey {
        case controlPosition, windowTitleVisibility, trafficLightVisibility, useEmbeddedElements
        case disableDockStyleTrafficLights, disableDockStyleTitles, showMinimizedHiddenLabels
        case enabledTrafficLightButtons, selectionOpacity, unselectedContentOpacity
        case hidePreviewCardBackground, previewHoverAction, titleOverflowStyle
        case useMonochromeTrafficLights, trafficLightButtonScale, switcherMaxRows
        case switcherScrollVertical, switcherIgnoreScreenLimit, appNameStyle
    }
}

struct DockPreviewPanelBackgroundOptions: Equatable {
    var style: DockPreviewBackgroundStyle
    var material: DockPreviewBackgroundMaterial
    var borderOpacity: Double
    var borderWidth: Double
    var useOpaqueBackground: Bool
    var highlightColorHex: String?
    var glassOpacity: Double
    var tintOpacity: Double
    var blurRadius: Double
    var saturation: Double

    static let `default` = DockPreviewPanelBackgroundOptions(
        style: .liquidGlass,
        material: .hudWindow,
        borderOpacity: 0.15,
        borderWidth: 1.0,
        useOpaqueBackground: false,
        highlightColorHex: nil,
        glassOpacity: 0.95,
        tintOpacity: 0.3,
        blurRadius: 0,
        saturation: 1.0
    )
}

extension DockPreviewPanelBackgroundOptions: Codable {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func d<T: Decodable>(_ key: CodingKeys, _ def: T) -> T { (try? c.decode(T.self, forKey: key)) ?? def }
        let s = DockPreviewPanelBackgroundOptions.default
        style = d(.style, s.style)
        material = d(.material, s.material)
        borderOpacity = d(.borderOpacity, s.borderOpacity)
        borderWidth = d(.borderWidth, s.borderWidth)
        useOpaqueBackground = d(.useOpaqueBackground, s.useOpaqueBackground)
        highlightColorHex = d(.highlightColorHex, s.highlightColorHex)
        glassOpacity = d(.glassOpacity, s.glassOpacity)
        tintOpacity = d(.tintOpacity, s.tintOpacity)
        blurRadius = d(.blurRadius, s.blurRadius)
        saturation = d(.saturation, s.saturation)
    }
}
