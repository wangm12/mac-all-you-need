import Core
import CoreGraphics
import Foundation
import SwiftUI

/// Observable bridge between `RadialMenuCoordinator` state and the puck HUD.
@MainActor
final class RadialMenuViewModel: ObservableObject {
    @Published var isShown = false
    @Published var showsChevron = true
    @Published var allowsIdleBreath = false
    @Published var showsFirstUseHint = false

    private let animationState = RadialPuckAnimationState()
    private var selection: RadialSelectionMath.Selection = .none
    private var cursorDelta: CGPoint = .zero
    private var labelText: String?
    private var previewFrame: CGRect?
    private var pointerHasMoved = false

    func update(
        from coordinator: RadialMenuCoordinator,
        axTrusted: Bool,
        hasTargetWindow: Bool,
        fillScreenHintDismissed: Bool
    ) {
        isShown = coordinator.state != .idle
        selection = coordinator.selection
        cursorDelta = coordinator.lastCursorDelta

        if let unavailability = coordinator.unavailability {
            labelText = RadialPuckLabelCopy.label(for: selection, unavailability: unavailability)
            previewFrame = nil
        } else if !axTrusted {
            labelText = RadialPuckLabelCopy.label(for: .none, unavailability: .accessibilityRequired)
            previewFrame = nil
        } else if !hasTargetWindow {
            labelText = RadialPuckLabelCopy.label(for: .none, unavailability: .noMovableWindow)
            previewFrame = nil
        } else {
            labelText = RadialPuckLabelCopy.label(for: selection, unavailability: nil)
            previewFrame = coordinator.proposedFrame
        }

        showsFirstUseHint = isShown && !fillScreenHintDismissed && !pointerHasMoved
        showsChevron = !fillScreenHintDismissed || selection == .ring(0) || selection == .fullScreen
        allowsIdleBreath = !pointerHasMoved && selection == .none
    }

    /// Latest damped HUD state. Not `@Published` — `TimelineView` reads this every frame;
    /// publishing it would re-enter SwiftUI's update graph and hang the main thread.
    var renderState: RadialPuckRenderState { animationState.renderState }

    func notePointerMoved() {
        noteUserEngaged()
    }

    func noteUserEngaged() {
        pointerHasMoved = true
        allowsIdleBreath = false
    }

    func snapPreviewToCommittedFrame(_ frame: CGRect?) {
        animationState.snapPreview(to: frame)
    }

    func applySettingsPreview(
        selection: RadialSelectionMath.Selection,
        cursorDelta: CGPoint,
        previewFrame: CGRect?,
        allowsIdleBreath: Bool,
        showsChevron: Bool
    ) {
        isShown = true
        self.selection = selection
        self.cursorDelta = cursorDelta
        self.previewFrame = previewFrame
        labelText = RadialPuckLabelCopy.label(for: selection, unavailability: nil)
        self.allowsIdleBreath = allowsIdleBreath
        self.showsChevron = showsChevron
        showsFirstUseHint = false
    }

    func resetSessionMotion() {
        pointerHasMoved = false
        animationState.reset()
    }

    @discardableResult
    func tick(now: TimeInterval, reduceMotion: Bool) -> RadialPuckRenderState {
        guard isShown else { return animationState.renderState }
        animationState.tick(
            now: now,
            selection: selection,
            cursorDelta: cursorDelta,
            labelText: labelText,
            previewFrame: previewFrame,
            reduceMotion: reduceMotion,
            allowsIdleBreath: allowsIdleBreath
        )
        return animationState.renderState
    }
}
