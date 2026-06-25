import Core
import CoreGraphics
import Foundation

struct RadialPuckRenderState: Equatable {
    var selectionActive: CGFloat = 0
    var labelOpacity: CGFloat = 0
    var fullScreenBlend: CGFloat = 0
    var rayRadius: CGFloat = 0
    var aimAngle: CGFloat = 0
    var previewOpacity: CGFloat = 0
    var previewCornerRadius: CGFloat = 13
    var idleBreath: CGFloat = 0.5
    var labelText: String?
    var selection: RadialSelectionMath.Selection = .none
    var dampedPreviewFrame: CGRect = .zero
}

@MainActor
final class RadialPuckAnimationState {
    private(set) var renderState = RadialPuckRenderState()
    private var lastTickTime: TimeInterval?
    private var breathPhase: CGFloat = 0
    private var hasPreviewFrame = false

    func reset() {
        renderState = RadialPuckRenderState()
        lastTickTime = nil
        breathPhase = 0
        hasPreviewFrame = false
    }

    func tick(
        now: TimeInterval,
        selection: RadialSelectionMath.Selection,
        cursorDelta: CGPoint,
        labelText: String?,
        previewFrame: CGRect?,
        reduceMotion: Bool,
        allowsIdleBreath: Bool
    ) {
        let dt: CGFloat
        if let lastTickTime {
            dt = CGFloat(min(0.033, max(0.001, now - lastTickTime)))
        } else {
            dt = 1.0 / 60.0
        }
        lastTickTime = now

        if allowsIdleBreath, !reduceMotion {
            breathPhase += dt * 0.0017
            renderState.idleBreath = sin(breathPhase) * 0.5 + 0.5
        } else {
            renderState.idleBreath = 0.5
        }

        let hasSelection = selection != .none && previewFrame != nil
        let targetActive: CGFloat = selection != .none ? 1 : 0
        let targetFullScreen: CGFloat = selection == .fullScreen ? 1 : 0
        let targetRayRadius = RadialSelectionMath.displayDistance(for: cursorDelta, selection: selection)
        let targetAngle = aimAngle(for: selection, cursorDelta: cursorDelta, hasSelection: selection != .none)

        if reduceMotion {
            renderState.selectionActive = targetActive
            renderState.labelOpacity = labelText == nil ? 0 : targetActive
            renderState.fullScreenBlend = targetFullScreen
            renderState.rayRadius = targetRayRadius
            renderState.aimAngle = targetAngle
            renderState.previewOpacity = hasSelection ? 1 : 0
            renderState.previewCornerRadius = RadialPuckVisualTokens.previewCornerRadius(fullScreenBlend: targetFullScreen)
            if let previewFrame {
                renderState.dampedPreviewFrame = previewFrame
                hasPreviewFrame = true
            } else {
                renderState.dampedPreviewFrame = .zero
                hasPreviewFrame = false
            }
        } else {
            renderState.selectionActive = RadialPuckDamping.damp(
                current: renderState.selectionActive, target: targetActive, lambda: 14, dt: dt
            )
            let labelTarget: CGFloat = labelText == nil ? 0 : targetActive
            renderState.labelOpacity = RadialPuckDamping.damp(
                current: renderState.labelOpacity, target: labelTarget, lambda: 12, dt: dt
            )
            renderState.fullScreenBlend = RadialPuckDamping.damp(
                current: renderState.fullScreenBlend, target: targetFullScreen, lambda: 12, dt: dt
            )
            renderState.rayRadius = RadialPuckDamping.damp(
                current: renderState.rayRadius, target: targetRayRadius, lambda: 16, dt: dt
            )
            let aimLambda: CGFloat = RadialSelectionMath.usesCursorAim(for: cursorDelta, selection: selection) ? 20 : 14
            renderState.aimAngle = RadialPuckDamping.dampAngle(
                current: renderState.aimAngle, target: targetAngle, lambda: aimLambda, dt: dt
            )
            let previewTargetOpacity: CGFloat = hasSelection ? 1 : 0
            let previewLambda: CGFloat = hasSelection ? 14 : 10
            renderState.previewOpacity = RadialPuckDamping.damp(
                current: renderState.previewOpacity, target: previewTargetOpacity, lambda: previewLambda, dt: dt
            )
            renderState.previewCornerRadius = RadialPuckDamping.damp(
                current: renderState.previewCornerRadius,
                target: RadialPuckVisualTokens.previewCornerRadius(fullScreenBlend: renderState.fullScreenBlend),
                lambda: 12,
                dt: dt
            )
            if let previewFrame {
                if hasPreviewFrame {
                    renderState.dampedPreviewFrame = RadialPuckDamping.dampRect(
                        current: renderState.dampedPreviewFrame,
                        target: previewFrame,
                        lambda: 15,
                        dt: dt
                    )
                } else {
                    renderState.dampedPreviewFrame = previewFrame
                    hasPreviewFrame = true
                }
            } else {
                hasPreviewFrame = false
            }
        }

        renderState.labelText = labelText
        renderState.selection = selection
    }

    private func aimAngle(
        for selection: RadialSelectionMath.Selection,
        cursorDelta: CGPoint,
        hasSelection: Bool
    ) -> CGFloat {
        guard hasSelection else { return renderState.aimAngle }
        if RadialSelectionMath.usesCursorAim(for: cursorDelta, selection: selection) {
            return RadialSelectionMath.aimAngleRadians(for: cursorDelta)
        }
        if case let .ring(index) = selection {
            return RadialMenuLayout.canonicalAngleRadians(forRingIndex: index)
        }
        return RadialSelectionMath.aimAngleRadians(for: cursorDelta)
    }

    /// Snaps damped preview to the committed frame so release does not lag behind the layout.
    func snapPreview(to frame: CGRect?) {
        guard let frame else { return }
        renderState.dampedPreviewFrame = frame
        renderState.previewOpacity = 1
        hasPreviewFrame = true
    }
}
