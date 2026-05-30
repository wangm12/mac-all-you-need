import CoreGraphics
import Core
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

    init(actionPerformer: any RadialActionPerforming, frameResolver: any ProposedFrameResolving) {
        self.actionPerformer = actionPerformer
        self.frameResolver = frameResolver
    }

    func open(at point: CGPoint) {
        state = .open(menuCenter: point)
        selection = .none
        proposedFrame = nil
    }

    func update(cursorAt current: CGPoint) {
        guard case let .open(center) = state else { return }
        let delta = CGPoint(x: current.x - center.x, y: current.y - center.y)
        selection = RadialSelectionMath.selection(from: delta)
        switch selection {
        case let .ring(index):
            if let action = RadialMenuLayout.action(forRingIndex: index) {
                proposedFrame = frameResolver.proposedFrame(for: action)
            } else {
                proposedFrame = nil
            }
        case .center:
            proposedFrame = frameResolver.proposedFrame(for: RadialMenuLayout.centerAction)
        case .none:
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
        case .none:
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
    }
}
