import AppKit
import Core
import Foundation

/// Shared timing thresholds for modifier-tap and double-tap detection.
public enum ModifierTapTiming {
    /// Maximum press duration (seconds) for a modifier press+release to count as a tap.
    public static let tapHoldMax: TimeInterval = 0.25

    /// Storage key for the user-configured double-tap speed preference.
    /// Value is a TimeInterval in seconds; 0.0 means "use system double-click interval".
    public static let multiTapWindowKey = "modifierTapWindow"

    /// Maximum gap (seconds) between consecutive taps of the same modifier.
    ///
    /// Reads the user preference first; falls back to `NSEvent.doubleClickInterval`
    /// (which honors the user's Accessibility → Pointer Control → Double-Click Speed
    /// setting). The system default is typically 0.45–0.5 s, which is more forgiving
    /// than the old hardcoded 0.28 s.
    public static var multiTapWindow: TimeInterval {
        let stored = AppGroupSettings.defaults.double(forKey: multiTapWindowKey)
        if stored > 0 { return stored }
        return min(max(NSEvent.doubleClickInterval, 0.20), 0.60)
    }
}
