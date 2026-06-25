import FeatureCore

/// Maps each HotkeyAction to the feature it belongs to.
/// Used by HotkeysSettingsView to grey-out rows when a feature is disabled.
extension HotkeyAction {
    var relatedFeatureID: FeatureID? {
        switch self {
        case .clipboard: return .clipboard
        case .browseFolder: return .folderPreview
        case .finderHistory: return .folderHistory
        case .windowHub: return .windowHub
        case .windowLeftHalf, .windowRightHalf, .windowTopHalf, .windowBottomHalf,
             .windowTopLeft, .windowTopRight, .windowBottomLeft, .windowBottomRight,
             .windowMaximize, .windowAlmostMaximize, .windowCenter, .windowRestore,
             .windowNextDisplay, .windowPreviousDisplay,
             .windowNextSpace, .windowPreviousSpace, .radialMenu:
            return .windowLayouts
        }
    }
}
