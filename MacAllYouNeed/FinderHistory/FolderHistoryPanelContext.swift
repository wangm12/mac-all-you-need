import Foundation

/// User-visible state for the hotkey history panel (recording gates vs. browsing history).
struct FolderHistoryPanelContext: Equatable {
    var isFeatureEnabled: Bool
    var isAccessibilityGranted: Bool
    var isPaused: Bool

    var emptyListHint: String {
        if !isFeatureEnabled {
            return "Enable Finder Folder History on the Dashboard to record folders."
        }
        if !isAccessibilityGranted {
            return "Grant Accessibility in Finder History settings, then browse folders in Finder."
        }
        if isPaused {
            return "Recording is paused. Turn off Pause in Finder History settings."
        }
        return "No folders in history yet. Open a few folders in Finder, wait a moment, then check again."
    }
}
