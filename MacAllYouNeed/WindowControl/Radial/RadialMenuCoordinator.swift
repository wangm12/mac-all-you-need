import Core
import CoreGraphics
import Foundation
import Observation

@MainActor
protocol RadialActionPerforming: AnyObject {
    func perform(action: WindowAction)
}

@MainActor
protocol ProposedFrameResolving: AnyObject {
    func proposedFrame(for action: WindowAction) -> CGRect?
}

/// Pure lifecycle state machine for the radial window-management menu.
/// UI controllers observe this; the event tap drives `open`/`update`/`commit`.
@MainActor
@Observable
final class RadialMenuCoordinator {
    enum State: Equatable {
        case idle
        case open(menuCenter: CGPoint)
        case committed(action: WindowAction)
        case cancelled
    }

    enum Unavailability: Equatable {
        case noMovableWindow
        case accessibilityRequired
        case cannotResize
    }

    private(set) var state: State = .idle
    private(set) var selection: RadialSelectionMath.Selection = .none
    private(set) var selectionState = RadialSelectionMath.SelectionState()
    private(set) var proposedFrame: CGRect?
    private(set) var unavailability: Unavailability?
    private(set) var lastCursorDelta: CGPoint = .zero

    private let actionPerformer: any RadialActionPerforming
    private let frameResolver: any ProposedFrameResolving
    private var edgeClamp: RadialSelectionMath.EdgeClamp?
    private var lastCursor: CGPoint?

    init(actionPerformer: any RadialActionPerforming, frameResolver: any ProposedFrameResolving) {
        self.actionPerformer = actionPerformer
        self.frameResolver = frameResolver
    }

    func open(at point: CGPoint, desktopBounds: CGRect? = nil) {
        state = .open(menuCenter: point)
        selection = .none
        selectionState = RadialSelectionMath.SelectionState()
        proposedFrame = nil
        unavailability = nil
        lastCursor = nil
        lastCursorDelta = .zero
        if let desktopBounds, !desktopBounds.isNull, !desktopBounds.isEmpty {
            edgeClamp = RadialSelectionMath.EdgeClamp(initial: point, desktopBounds: desktopBounds)
        } else {
            edgeClamp = nil
        }
    }

    func select(action: WindowAction) {
        guard case .open = state else { return }
        if action == RadialMenuLayout.fillScreenAction {
            selection = .fullScreen
            selectionState.isArmed = true
            selectionState.isFullScreen = true
            selectionState.lastRingIndex = 0
            lastCursorDelta = RadialSelectionMath.syntheticDelta(for: .fullScreen)
        } else if let index = RadialMenuLayout.ringIndex(for: action) {
            selection = .ring(index)
            selectionState.isArmed = true
            selectionState.isFullScreen = false
            selectionState.lastRingIndex = index
            lastCursorDelta = RadialSelectionMath.syntheticDelta(for: .ring(index))
        } else {
            return
        }
        applySelectionFrame()
    }

    func update(cursorAt current: CGPoint) {
        guard case let .open(center) = state else { return }
        let resolved: CGPoint
        if var clamp = edgeClamp {
            let prior = lastCursor ?? current
            let deltaX = current.x - prior.x
            let deltaY = current.y - prior.y
            resolved = clamp.resolve(current: current, deltaX: deltaX, deltaY: deltaY)
            edgeClamp = clamp
        } else {
            resolved = current
        }
        lastCursor = resolved
        let delta = CGPoint(x: resolved.x - center.x, y: resolved.y - center.y)
        lastCursorDelta = delta
        selection = RadialSelectionMath.selection(
            from: delta,
            state: &selectionState,
            now: ProcessInfo.processInfo.systemUptime
        )
        applySelectionFrame()
    }

    func setUnavailability(_ reason: Unavailability?) {
        unavailability = reason
        if reason != nil {
            proposedFrame = nil
        }
    }

    func clearSelection() {
        guard case .open = state else { return }
        selection = .none
        selectionState = RadialSelectionMath.SelectionState()
        proposedFrame = nil
        lastCursorDelta = .zero
    }

    private func applySelectionFrame() {
        if unavailability != nil {
            proposedFrame = nil
            return
        }
        guard let action = RadialSelectionMath.action(for: selection) else {
            proposedFrame = nil
            return
        }
        proposedFrame = frameResolver.proposedFrame(for: action)
    }

    func commit() {
        guard case .open = state else {
            cancel()
            return
        }
        guard unavailability == nil else {
            cancel()
            return
        }
        if let action = RadialSelectionMath.action(for: selection) {
            state = .committed(action: action)
            actionPerformer.perform(action: action)
        } else {
            cancel()
        }
    }

    func cancel() {
        state = .cancelled
        selection = .none
        selectionState = RadialSelectionMath.SelectionState()
        proposedFrame = nil
        unavailability = nil
        lastCursorDelta = .zero
    }

    func reset() {
        state = .idle
        selection = .none
        selectionState = RadialSelectionMath.SelectionState()
        proposedFrame = nil
        unavailability = nil
        edgeClamp = nil
        lastCursor = nil
        lastCursorDelta = .zero
    }
}
