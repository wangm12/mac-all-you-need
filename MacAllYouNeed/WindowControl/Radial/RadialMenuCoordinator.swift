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

    private(set) var state: State = .idle
    private(set) var selection: RadialSelectionMath.Selection = .none
    private(set) var proposedFrame: CGRect?

    private let actionPerformer: any RadialActionPerforming
    private let frameResolver: any ProposedFrameResolving
    private var edgeClamp: RadialSelectionMath.EdgeClamp?
    private var lastCursor: CGPoint?

    init(actionPerformer: any RadialActionPerforming, frameResolver: any ProposedFrameResolving) {
        self.actionPerformer = actionPerformer
        self.frameResolver = frameResolver
    }

    func open(at point: CGPoint, screenBounds: CGRect? = nil) {
        state = .open(menuCenter: point)
        selection = .none
        proposedFrame = nil
        lastCursor = nil
        if let screenBounds {
            edgeClamp = RadialSelectionMath.EdgeClamp(initial: point, screenBounds: screenBounds)
        } else {
            edgeClamp = nil
        }
    }

    func select(action: WindowAction) {
        guard case let .open(center) = state else { return }
        if let index = RadialMenuLayout.ringActions.firstIndex(of: action) {
            selection = .ring(index)
        } else if action == RadialMenuLayout.centerAction {
            selection = .center
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
        selection = RadialSelectionMath.selection(from: delta, cursor: resolved, menuCenter: center)
        applySelectionFrame()
    }

    /// Selects the close pill without dismissing; commit or Esc dismisses.
    func selectClose() {
        guard case .open = state else { return }
        selection = .cancel
        proposedFrame = nil
    }

    func clearSelection() {
        guard case .open = state else { return }
        selection = .none
        proposedFrame = nil
    }

    private func applySelectionFrame() {
        switch selection {
        case let .ring(index):
            if let action = RadialMenuLayout.action(forRingIndex: index) {
                proposedFrame = frameResolver.proposedFrame(for: action)
            } else {
                proposedFrame = nil
            }
        case .center:
            proposedFrame = frameResolver.proposedFrame(for: RadialMenuLayout.centerAction)
        case .none, .cancel:
            proposedFrame = nil
        }
    }

    func commit() {
        guard case .open = state else {
            cancel()
            return
        }
        let action: WindowAction?
        switch selection {
        case let .ring(index):
            action = RadialMenuLayout.action(forRingIndex: index)
        case .center:
            action = RadialMenuLayout.centerAction
        case .none, .cancel:
            action = nil
        }
        if let action {
            state = .committed(action: action)
            actionPerformer.perform(action: action)
        } else {
            cancel()
        }
    }

    func cancel() {
        state = .cancelled
        selection = .none
        proposedFrame = nil
    }

    func reset() {
        state = .idle
        selection = .none
        proposedFrame = nil
        edgeClamp = nil
        lastCursor = nil
    }
}
