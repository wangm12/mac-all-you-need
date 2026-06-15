import Foundation

/// Latest move-path diagnostics for debug surfaces (zero-cost in release when unset).
public enum WindowControlMoveDiagnostics: Sendable {
  public struct Snapshot: Equatable, Sendable {
    public var axRoundTrips: Int
    public var durationMilliseconds: Double

    public init(axRoundTrips: Int = 0, durationMilliseconds: Double = 0) {
      self.axRoundTrips = axRoundTrips
      self.durationMilliseconds = durationMilliseconds
    }
  }

  private static let lock = NSLock()
  private static var _latest = Snapshot()

  public static var latest: Snapshot {
    lock.lock()
    defer { lock.unlock() }
    return _latest
  }

  public static func record(axRoundTrips: Int, durationMilliseconds: Double) {
    lock.lock()
    defer { lock.unlock() }
    _latest = Snapshot(axRoundTrips: axRoundTrips, durationMilliseconds: durationMilliseconds)
  }

  #if DEBUG
  public static func resetForTesting() {
    lock.lock()
    defer { lock.unlock() }
    _latest = Snapshot()
  }
  #endif
}
