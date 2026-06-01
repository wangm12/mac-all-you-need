import Foundation

/// Shared timing thresholds for modifier-tap and double-tap detection.
public enum ModifierTapTiming {
    /// Maximum press duration (seconds) for a modifier press+release to count as a tap.
    public static let tapHoldMax: TimeInterval = 0.25

    /// Maximum gap (seconds) between consecutive taps of the same modifier.
    public static let multiTapWindow: TimeInterval = 0.28
}
