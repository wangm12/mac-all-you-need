import Foundation
import SwiftUI

// MARK: - Sort orders

enum DockSortOrder: String, Codable, CaseIterable, Identifiable {
    case recentlyUsed
    case creationOrder
    case alphabeticalByTitle
    case alphabeticalByAppName

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .recentlyUsed: "Recently used"
        case .creationOrder: "Creation order"
        case .alphabeticalByTitle: "Title (A–Z)"
        case .alphabeticalByAppName: "App name (A–Z)"
        }
    }
}

// MARK: - Window switcher

enum DockSwitcherPlacementStrategy: String, Codable, CaseIterable, Identifiable {
    case screenWithMouse
    case screenWithLastActive
    case pinnedToScreen

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .screenWithMouse: "Screen with mouse"
        case .screenWithLastActive: "Screen with last active window"
        case .pinnedToScreen: "Pinned to screen"
        }
    }
}

enum DockSwitcherMouseFollowsFocus: String, Codable, CaseIterable, Identifiable {
    case never
    case always
    case differentDisplayOnly

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .never: "Never"
        case .always: "Always"
        case .differentDisplayOnly: "Different display only"
        }
    }
}

enum DockSwitcherLayoutStyle: String, Codable, CaseIterable, Identifiable {
    case horizontalGrid
    case verticalList

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .horizontalGrid: "Horizontal grid"
        case .verticalList: "Vertical list (with search)"
        }
    }
}

enum DockSwitcherScrollDirection: String, Codable, CaseIterable, Identifiable {
    case horizontal
    case vertical

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .horizontal: "Horizontal"
        case .vertical: "Vertical"
        }
    }
}

enum DockSwitcherInvocationMode: String, Codable, CaseIterable, Identifiable {
    case allWindows
    case activeAppOnly
    case currentSpaceOnly
    case activeAppCurrentSpace

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .allWindows: "All windows"
        case .activeAppOnly: "Active app only"
        case .currentSpaceOnly: "Current space only"
        case .activeAppCurrentSpace: "Active app, current space"
        }
    }
}

// MARK: - Cmd+Tab

enum DockCmdTabAppNameStyle: String, Codable, CaseIterable, Identifiable {
    case `default`
    case shadowed
    case popover

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .default: "Default"
        case .shadowed: "Shadowed"
        case .popover: "Popover"
        }
    }
}

enum DockWindowTitlePosition: String, Codable, CaseIterable, Identifiable {
    case bottomLeft
    case bottomRight
    case topRight
    case topLeft

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .bottomLeft: "Bottom left"
        case .bottomRight: "Bottom right"
        case .topRight: "Top right"
        case .topLeft: "Top left"
        }
    }
}

enum DockTrafficLightPosition: String, Codable, CaseIterable, Identifiable {
    case topLeft
    case topRight
    case bottomRight
    case bottomLeft

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .topLeft: "Top left"
        case .topRight: "Top right"
        case .bottomRight: "Bottom right"
        case .bottomLeft: "Bottom left"
        }
    }
}

// MARK: - Appearance (shared)

enum DockWindowTitleVisibilityMode: String, Codable, CaseIterable, Identifiable {
    case whenHoveringPreview
    case alwaysVisible

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .whenHoveringPreview: "On preview hover"
        case .alwaysVisible: "Always visible"
        }
    }
}

enum DockWindowTitleFontSize: String, Codable, CaseIterable, Identifiable {
    case system
    case caption2
    case caption
    case footnote
    case subheadline
    case body
    case headline
    case title3

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: "System default"
        case .caption2: "Caption 2"
        case .caption: "Caption"
        case .footnote: "Footnote"
        case .subheadline: "Subheadline"
        case .body: "Body"
        case .headline: "Headline"
        case .title3: "Title 3"
        }
    }

    var font: Font {
        switch self {
        case .system: .subheadline
        case .caption2: .caption2
        case .caption: .caption
        case .footnote: .footnote
        case .subheadline: .subheadline
        case .body: .body
        case .headline: .headline
        case .title3: .title3
        }
    }
}

enum DockTitleOverflowStyle: String, Codable, CaseIterable, Identifiable {
    case truncateTail
    case truncateMiddle
    case truncateHead
    case marquee

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .truncateTail: "Truncate end"
        case .truncateMiddle: "Truncate middle"
        case .truncateHead: "Truncate start"
        case .marquee: "Marquee scroll"
        }
    }
}

enum DockTrafficLightVisibilityMode: String, Codable, CaseIterable, Identifiable {
    case never
    case dimmedOnPreviewHover
    case fullOpacityOnPreviewHover
    case alwaysVisible

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .never: "Never visible"
        case .dimmedOnPreviewHover: "On hover; dimmed"
        case .fullOpacityOnPreviewHover: "On hover; full opacity"
        case .alwaysVisible: "Always visible"
        }
    }
}

enum DockAppNameStyle: String, Codable, CaseIterable, Identifiable {
    case `default`
    case shadowed
    case popover

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .default: "Default"
        case .shadowed: "Shadowed"
        case .popover: "Popover pill"
        }
    }
}

enum DockAppearanceMode: String, Codable, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}

enum DockWindowTitleDisplayCondition: String, Codable, CaseIterable, Identifiable {
    case all
    case dockPreviewsOnly
    case windowSwitcherOnly

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .all: "All contexts"
        case .dockPreviewsOnly: "Dock previews only"
        case .windowSwitcherOnly: "Window switcher only"
        }
    }
}

enum DockCompactModeTitleFormat: String, Codable, CaseIterable, Identifiable {
    case appNameAndTitle
    case titleOnly
    case appNameOnly

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .appNameAndTitle: "App name & title"
        case .titleOnly: "Title only"
        case .appNameOnly: "App name only"
        }
    }
}

enum DockCompactModeItemSize: String, Codable, CaseIterable, Identifiable {
    case xSmall
    case small
    case medium
    case large
    case xLarge
    case xxLarge
    case xxxLarge

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .xSmall: "XS"
        case .small: "S"
        case .medium: "M"
        case .large: "L"
        case .xLarge: "XL"
        case .xxLarge: "XXL"
        case .xxxLarge: "XXXL"
        }
    }
}

// MARK: - Background

enum DockBackgroundStyleFull: String, Codable, CaseIterable, Identifiable {
    case liquidGlass
    case frostedMaterial
    case clear

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .liquidGlass: "Liquid Glass"
        case .frostedMaterial: "Frosted Glass"
        case .clear: "Clear"
        }
    }
}

enum DockBackgroundMaterialFull: String, Codable, CaseIterable, Identifiable {
    case ultraThin
    case thin
    case regular
    case thick
    case ultraThick

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ultraThin: "Ultra Thin"
        case .thin: "Thin"
        case .regular: "Regular"
        case .thick: "Thick"
        case .ultraThick: "Ultra Thick"
        }
    }
}

// MARK: - Gesture enums

enum DockScrollGestureBehavior: String, Codable, CaseIterable, Identifiable {
    case activateHide
    case bringToCurrentSpace

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .activateHide: "Activate / Hide"
        case .bringToCurrentSpace: "Bring to current space"
        }
    }
}

enum DockScrollGestureMediaBehavior: String, Codable, CaseIterable, Identifiable {
    case adjustVolume
    case activateHide

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .adjustVolume: "Adjust volume"
        case .activateHide: "Activate / Hide"
        }
    }
}

enum DockWindowSwipeAction: String, Codable, CaseIterable, Identifiable {
    case none
    case minimize
    case maximize
    case close
    case quit
    case toggleFullScreen

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: "None"
        case .minimize: "Minimize"
        case .maximize: "Maximize"
        case .close: "Close"
        case .quit: "Quit"
        case .toggleFullScreen: "Toggle Fullscreen"
        }
    }
}

enum DockMiddleClickAction: String, Codable, CaseIterable, Identifiable {
    case close
    case minimize
    case quit
    case none

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .close: "Close"
        case .minimize: "Minimize"
        case .quit: "Quit"
        case .none: "None"
        }
    }
}

enum DockClickAction: String, Codable, CaseIterable, Identifiable {
    case minimize
    case hide

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .minimize: "Minimize"
        case .hide: "Hide"
        }
    }
}

enum DockAeroShakeAction: String, Codable, CaseIterable, Identifiable {
    case none
    case all
    case except

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: "None"
        case .all: "Minimize all other windows"
        case .except: "Minimize all except this"
        }
    }
}

enum DockTitleBarSizingMode: String, Codable, CaseIterable, Identifiable {
    case uniform
    case separate

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .uniform: "Uniform"
        case .separate: "Width & Height separately"
        }
    }
}

enum DockMediaScrollBehavior: String, Codable, CaseIterable, Identifiable {
    case adjustVolume
    case seekPlayback

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .adjustVolume: "Adjust volume"
        case .seekPlayback: "Seek playback"
        }
    }
}

enum DockMediaScrollDirection: String, Codable, CaseIterable, Identifiable {
    case vertical
    case horizontal

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .vertical: "Vertical"
        case .horizontal: "Horizontal"
        }
    }
}

enum DockFolderSortOrder: String, Codable, CaseIterable, Identifiable {
    case dateModified
    case name
    case kind
    case size

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .dateModified: "Date modified"
        case .name: "Name"
        case .kind: "Kind"
        case .size: "Size"
        }
    }
}

enum DockMediaDetectionMode: String, Codable, CaseIterable, Identifiable {
    case universal
    case appleScriptOnly

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .universal: "Universal (any app)"
        case .appleScriptOnly: "Apple Music & Spotify only"
        }
    }
}

// MARK: - Capture / live preview

enum DockWindowImageCaptureQuality: String, Codable, CaseIterable, Identifiable {
    case nominal
    case best

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .nominal: "Nominal"
        case .best: "Best"
        }
    }
}

enum DockLivePreviewQuality: String, Codable, CaseIterable, Identifiable {
    case thumbnail
    case low
    case standard
    case high
    case retina
    case native

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .thumbnail: "Thumbnail"
        case .low: "Low"
        case .standard: "Standard"
        case .high: "High"
        case .retina: "Retina"
        case .native: "Native"
        }
    }
}

enum DockLivePreviewFrameRate: Int, Codable, CaseIterable, Identifiable {
    case fps5 = 5
    case fps10 = 10
    case fps15 = 15
    case fps24 = 24
    case fps30 = 30
    case fps60 = 60
    case fps120 = 120

    var id: Int { rawValue }

    var displayName: String { "\(rawValue) fps" }
}

enum DockLivePreviewScope: String, Codable, CaseIterable, Identifiable {
    case selectedWindowOnly
    case selectedAppWindows
    case allWindows

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .selectedWindowOnly: "Selected window only"
        case .selectedAppWindows: "Selected app's windows"
        case .allWindows: "All visible windows"
        }
    }
}

// MARK: - Dock click interaction

enum DockPreviewHoverAction: String, Codable, CaseIterable, Identifiable {
    case none
    case tap
    case fullSizePreview

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: "None"
        case .tap: "Simulate click"
        case .fullSizePreview: "Full-size preview"
        }
    }
}