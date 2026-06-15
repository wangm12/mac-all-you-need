import Core
import Foundation

/// Pure decision logic for per-window move coalescing during the settling window.
public enum WindowMoveCoalescing {
  public static let defaultSettlingWindow: TimeInterval = 0.05

  /// Returns true when a newer action for the same window should supersede an in-flight
  /// move that is still within the settling window.
  public static func shouldSupersedeInFlightMove(
    sameWindow: Bool,
    inFlightStartedAt: Date,
    now: Date,
    settlingWindow: TimeInterval = defaultSettlingWindow
  ) -> Bool {
    guard sameWindow else { return false }
    return now.timeIntervalSince(inFlightStartedAt) < settlingWindow
  }
}
