import CoreGraphics
import Foundation

/// Moves a window by applying AX position deltas during a grab gesture.
///
/// Browsers such as Chrome interpret synthetic title-bar mouse events as tab
/// drags. This strategy moves the resolved shell window directly instead.
public final class AXPointerDragStrategy {
    public let configuration: NativeWindowDragConfiguration

    private var dragStartLocation: CGPoint?
    private var initialOrigin: CGPoint?
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
            updateDrag(to: location, target: target, axTrusted: axTrusted)
        case let .mouseUp(location, axTrusted):
            endDrag(at: location, axTrusted: axTrusted)
        }
    }

    public func cancel() {
        dragStartLocation = nil
        initialOrigin = nil
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
        initialOrigin = target.frame.origin
        return .suppress
    }

    private func updateDrag(
        to location: CGPoint,
        target: (any WindowMovableElement)?,
        axTrusted: Bool
    ) -> NativeWindowDragDecision {
        guard axTrusted else {
            cancel()
            return .passThrough
        }
        guard let dragStartLocation,
              let initialOrigin,
              let target
        else {
            return .passThrough
        }

        let delta = CGPoint(x: location.x - dragStartLocation.x, y: location.y - dragStartLocation.y)
        guard didDrag || hypot(delta.x, delta.y) >= configuration.movementThreshold else {
            return .suppress
        }

        didDrag = true
        _ = target.setPosition(
            CGPoint(x: initialOrigin.x + delta.x, y: initialOrigin.y + delta.y)
        )
        return .suppress
    }

    private func endDrag(at _: CGPoint, axTrusted: Bool) -> NativeWindowDragDecision {
        guard axTrusted else {
            cancel()
            return .passThrough
        }
        defer { cancel() }
        return .suppress
    }

    private func isValid(frame: CGRect) -> Bool {
        !frame.isNull && !frame.isEmpty && frame.width.isFinite && frame.height.isFinite
    }
}
