import CoreGraphics

public struct WindowSnapIntentConfiguration: Equatable, Sendable {
    public var movementThreshold: CGFloat
    public var edgeThreshold: CGFloat
    public var cornerThreshold: CGFloat
    public var sideHalfThreshold: CGFloat

    public init(
        movementThreshold: CGFloat = 12,
        edgeThreshold: CGFloat = 24,
        cornerThreshold: CGFloat = 96,
        sideHalfThreshold: CGFloat = 160
    ) {
        self.movementThreshold = movementThreshold
        self.edgeThreshold = edgeThreshold
        self.cornerThreshold = cornerThreshold
        self.sideHalfThreshold = sideHalfThreshold
    }
}

public struct WindowSnapIntentTracker: Equatable, Sendable {
    public let configuration: WindowSnapIntentConfiguration

    public private(set) var startPoint: CGPoint?
    public private(set) var startZone: WindowSnapZone = .inside
    public private(set) var currentZone: WindowSnapZone = .inside
    public private(set) var didMoveBeyondThreshold = false
    public private(set) var exitedInitialSnapZone = false
    public private(set) var armedZone: WindowSnapZone?

    private var startVisibleFrame: CGRect?

    public init(configuration: WindowSnapIntentConfiguration = WindowSnapIntentConfiguration()) {
        self.configuration = configuration
    }

    public var isArmed: Bool {
        armedAction != nil
    }

    public var armedAction: WindowAction? {
        armedZone?.action
    }

    public mutating func begin(at point: CGPoint, visibleFrame: CGRect) {
        startPoint = point
        startVisibleFrame = visibleFrame
        startZone = zone(for: point, in: visibleFrame)
        currentZone = startZone
        didMoveBeyondThreshold = false
        exitedInitialSnapZone = startZone.action == nil
        armedZone = nil
    }

    @discardableResult
    public mutating func update(at point: CGPoint, visibleFrame: CGRect) -> WindowSnapZone? {
        guard let startPoint else {
            return nil
        }

        let zone = zone(for: point, in: visibleFrame)
        currentZone = zone

        if distance(from: startPoint, to: point) >= configuration.movementThreshold {
            didMoveBeyondThreshold = true
        }

        if startZone.action != nil {
            if zone.action == nil || visibleFrame != startVisibleFrame {
                exitedInitialSnapZone = true
            }
        }

        guard didMoveBeyondThreshold,
              zone.action != nil,
              exitedInitialSnapZone
        else {
            armedZone = nil
            return nil
        }

        armedZone = zone
        return zone
    }

    public mutating func commit() -> WindowAction? {
        let action = armedAction
        reset()
        return action
    }

    public mutating func reset() {
        startPoint = nil
        startVisibleFrame = nil
        startZone = .inside
        currentZone = .inside
        didMoveBeyondThreshold = false
        exitedInitialSnapZone = false
        armedZone = nil
    }

    private func zone(for point: CGPoint, in visibleFrame: CGRect) -> WindowSnapZone {
        WindowSnapZone.zone(
            for: point,
            in: visibleFrame,
            edgeThreshold: configuration.edgeThreshold,
            cornerThreshold: configuration.cornerThreshold,
            sideHalfThreshold: configuration.sideHalfThreshold
        )
    }

    private func distance(from lhs: CGPoint, to rhs: CGPoint) -> CGFloat {
        hypot(rhs.x - lhs.x, rhs.y - lhs.y)
    }
}
