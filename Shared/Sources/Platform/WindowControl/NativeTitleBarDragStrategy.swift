import CoreGraphics
import Foundation

public struct NativeWindowDragConfiguration: Equatable, Sendable {
    public var titleBarYOffset: CGFloat
    public var movementThreshold: CGFloat

    public init(titleBarYOffset: CGFloat = 8, movementThreshold: CGFloat = 3) {
        self.titleBarYOffset = titleBarYOffset
        self.movementThreshold = movementThreshold
    }
}

public typealias NativeTitleBarDragConfiguration = NativeWindowDragConfiguration

public enum NativeWindowDragEvent: Equatable, Sendable {
    case mouseDown(at: CGPoint, axTrusted: Bool)
    case mouseDragged(to: CGPoint, axTrusted: Bool)
    case mouseUp(at: CGPoint, axTrusted: Bool)
}

public typealias NativeTitleBarDragEvent = NativeWindowDragEvent

public enum NativeWindowDragOutputEventType: Equatable, Sendable {
    case mouseDown
    case mouseDragged
    case mouseUp
}

public enum NativeWindowDragDecision: Equatable, Sendable {
    case passThrough
    case suppress
    case rewrite(type: NativeWindowDragOutputEventType, location: CGPoint)
    case replayClick(down: CGPoint, up: CGPoint)
}

public typealias NativeTitleBarDragDecision = NativeWindowDragDecision

public enum WindowTitleBarDragRegion {
    public static let defaultHeight: CGFloat = 56

    public static func contains(
        _ point: CGPoint,
        in frame: CGRect,
        height: CGFloat = defaultHeight
    ) -> Bool {
        guard !frame.isNull, !frame.isEmpty else { return false }
        let dragHeight = min(max(0, height), frame.height)
        let region = CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: dragHeight)
        return region.contains(point)
    }
}

public final class NativeWindowDragStrategy {
    public let configuration: NativeWindowDragConfiguration

    private var dragStartLocation: CGPoint?
    private var rewrittenMouseDownLocation: CGPoint?
    public private(set) var didDrag = false

    public init(configuration: NativeWindowDragConfiguration = NativeWindowDragConfiguration()) {
        self.configuration = configuration
    }

    public var isActive: Bool {
        dragStartLocation != nil
    }

    public func handle(
        _ event: NativeWindowDragEvent,
        target: (any WindowMovableElement)? = nil
    ) -> NativeWindowDragDecision {
        switch event {
        case let .mouseDown(location, axTrusted):
            beginDrag(at: location, target: target, axTrusted: axTrusted)
        case let .mouseDragged(location, axTrusted):
            updateDrag(to: location, axTrusted: axTrusted)
        case let .mouseUp(location, axTrusted):
            endDrag(at: location, axTrusted: axTrusted)
        }
    }

    public func cancel() {
        dragStartLocation = nil
        rewrittenMouseDownLocation = nil
        didDrag = false
    }

    private func beginDrag(
        at location: CGPoint,
        target: (any WindowMovableElement)?,
        axTrusted: Bool
    ) -> NativeWindowDragDecision {
        cancel()
        guard axTrusted,
              let target,
              target.isSupportedForWindowControl,
              target.isMovable,
              isValid(frame: target.frame)
        else {
            return .passThrough
        }

        dragStartLocation = location
        rewrittenMouseDownLocation = titleBarMouseDownLocation(for: location, in: target.frame)
        return .suppress
    }

    private func updateDrag(to location: CGPoint, axTrusted: Bool) -> NativeWindowDragDecision {
        guard axTrusted else {
            cancel()
            return .passThrough
        }
        guard let dragStartLocation,
              let rewrittenMouseDownLocation
        else {
            return .passThrough
        }

        guard didDrag || distance(from: dragStartLocation, to: location) >= configuration.movementThreshold else {
            return .suppress
        }

        let rewrittenLocation = CGPoint(
            x: rewrittenMouseDownLocation.x + location.x - dragStartLocation.x,
            y: rewrittenMouseDownLocation.y + location.y - dragStartLocation.y
        )
        if didDrag {
            return .rewrite(type: .mouseDragged, location: rewrittenLocation)
        } else {
            didDrag = true
            return .rewrite(type: .mouseDown, location: rewrittenMouseDownLocation)
        }
    }

    private func endDrag(at location: CGPoint, axTrusted: Bool) -> NativeWindowDragDecision {
        guard axTrusted else {
            cancel()
            return .passThrough
        }
        guard let dragStartLocation,
              let rewrittenMouseDownLocation
        else {
            return .passThrough
        }

        let decision: NativeWindowDragDecision = if didDrag {
            .rewrite(
                type: .mouseUp,
                location: CGPoint(
                    x: rewrittenMouseDownLocation.x + location.x - dragStartLocation.x,
                    y: rewrittenMouseDownLocation.y + location.y - dragStartLocation.y
                )
            )
        } else {
            .replayClick(down: dragStartLocation, up: location)
        }
        cancel()
        return decision
    }

    private func titleBarMouseDownLocation(for point: CGPoint, in frame: CGRect) -> CGPoint {
        let yOffset = min(max(0, configuration.titleBarYOffset), max(0, frame.height))
        return CGPoint(
            x: min(max(point.x, frame.minX), frame.maxX),
            y: frame.minY + yOffset
        )
    }

    private func distance(from lhs: CGPoint, to rhs: CGPoint) -> CGFloat {
        hypot(rhs.x - lhs.x, rhs.y - lhs.y)
    }

    private func isValid(frame: CGRect) -> Bool {
        !frame.isNull && !frame.isEmpty && frame.width.isFinite && frame.height.isFinite
    }
}

public typealias NativeTitleBarDragStrategy = NativeWindowDragStrategy
