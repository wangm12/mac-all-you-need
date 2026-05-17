import CoreGraphics
import Foundation

public struct NativeTitleBarDragConfiguration: Equatable, Sendable {
    public var titleBarYOffset: CGFloat

    public init(titleBarYOffset: CGFloat = 8) {
        self.titleBarYOffset = titleBarYOffset
    }
}

public enum NativeTitleBarDragEvent: Equatable, Sendable {
    case mouseDown(at: CGPoint, axTrusted: Bool)
    case mouseDragged(to: CGPoint, axTrusted: Bool)
    case mouseUp(at: CGPoint, axTrusted: Bool)
}

public typealias NativeTitleBarDragDecision = WindowEventTapMouseDownDecision

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

public final class NativeTitleBarDragStrategy {
    public let configuration: NativeTitleBarDragConfiguration

    private weak var activeTarget: (any WindowMovableElement)?
    private var dragStartLocation: CGPoint?
    private var dragStartFrame: CGRect?
    private var previousEnhancedUserInterface: Bool?
    private var didDrag = false

    public init(configuration: NativeTitleBarDragConfiguration = NativeTitleBarDragConfiguration()) {
        self.configuration = configuration
    }

    public var isActive: Bool {
        activeTarget != nil
    }

    public func handle(
        _ event: NativeTitleBarDragEvent,
        target: (any WindowMovableElement)? = nil
    ) -> NativeTitleBarDragDecision {
        switch event {
        case let .mouseDown(location, axTrusted):
            return beginDrag(at: location, target: target, axTrusted: axTrusted)
        case let .mouseDragged(location, axTrusted):
            return updateDrag(to: location, axTrusted: axTrusted)
        case let .mouseUp(_, axTrusted):
            return endDrag(axTrusted: axTrusted)
        }
    }

    public func cancel() {
        restoreEnhancedUserInterfaceIfNeeded()
        activeTarget = nil
        dragStartLocation = nil
        dragStartFrame = nil
        didDrag = false
    }

    private func beginDrag(
        at location: CGPoint,
        target: (any WindowMovableElement)?,
        axTrusted: Bool
    ) -> NativeTitleBarDragDecision {
        cancel()
        guard axTrusted,
              let target,
              target.isSupportedForWindowControl,
              target.isMovable
        else {
            return .passThrough
        }

        activeTarget = target
        dragStartLocation = location
        dragStartFrame = target.frame
        previousEnhancedUserInterface = target.enhancedUserInterfaceEnabled
        if previousEnhancedUserInterface != nil {
            _ = target.setEnhancedUserInterfaceEnabled(false)
        }
        return .passThrough
    }

    private func updateDrag(to location: CGPoint, axTrusted: Bool) -> NativeTitleBarDragDecision {
        guard axTrusted else {
            cancel()
            return .passThrough
        }
        guard let activeTarget,
              let dragStartLocation,
              let dragStartFrame
        else {
            return .passThrough
        }

        let proposedOrigin = CGPoint(
            x: dragStartFrame.origin.x + location.x - dragStartLocation.x,
            y: dragStartFrame.origin.y + location.y - dragStartLocation.y
        )
        guard activeTarget.setPosition(proposedOrigin) else {
            cancel()
            return .passThrough
        }

        didDrag = true
        return .suppress
    }

    private func endDrag(axTrusted: Bool) -> NativeTitleBarDragDecision {
        guard axTrusted else {
            cancel()
            return .passThrough
        }
        let shouldSuppress = didDrag
        cancel()
        return shouldSuppress ? .suppress : .passThrough
    }

    private func restoreEnhancedUserInterfaceIfNeeded() {
        if let previousEnhancedUserInterface, let activeTarget {
            _ = activeTarget.setEnhancedUserInterfaceEnabled(previousEnhancedUserInterface)
        }
        self.previousEnhancedUserInterface = nil
    }
}
