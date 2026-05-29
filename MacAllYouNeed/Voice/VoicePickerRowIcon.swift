import Foundation

/// Row icon for voice two-pane pickers: bundled brand mark or SF Symbol fallback.
enum VoicePickerRowIcon: Hashable {
    case brandAsset(String)
    case systemSymbol(String)
}
