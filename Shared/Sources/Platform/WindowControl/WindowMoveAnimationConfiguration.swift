import Foundation

public struct WindowMoveAnimationConfiguration: Equatable, Sendable {
    public var enabled: Bool
    public var stepCount: Int
    public var totalDuration: TimeInterval
    public var reduceMotion: Bool

    public init(
        enabled: Bool = false,
        stepCount: Int = 6,
        totalDuration: TimeInterval = 0.12,
        reduceMotion: Bool = false
    ) {
        self.enabled = enabled
        self.stepCount = max(1, stepCount)
        self.totalDuration = max(0, totalDuration)
        self.reduceMotion = reduceMotion
    }

    public static let instant = WindowMoveAnimationConfiguration()

    public var shouldAnimate: Bool {
        enabled && !reduceMotion && totalDuration > 0
    }

    public var stepInterval: TimeInterval {
        guard shouldAnimate else { return 0 }
        return totalDuration / Double(stepCount)
    }
}
