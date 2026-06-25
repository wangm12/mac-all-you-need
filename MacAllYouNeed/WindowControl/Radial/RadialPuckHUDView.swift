import Core
import SwiftUI

/// Radial Puck HUD — gesture-based window layout selector.
struct RadialPuckHUDView: View {
    let renderState: RadialPuckRenderState
    var showsChevron: Bool = true
    var allowsIdleBreath: Bool = false

    private var center: CGPoint {
        RadialPuckMetrics.circleCenterInPanel
    }

    var body: some View {
        Canvas { context, size in
            let cx = center.x
            let cy = center.y
            let active = renderState.selectionActive
            let full = renderState.fullScreenBlend
            let breath = allowsIdleBreath ? renderState.idleBreath : 0.5

            drawGuideRing(context: &context, cx: cx, cy: cy, active: active)
            if showsChevron {
                drawChevron(context: &context, cx: cx, cy: cy, full: full)
            }
            drawAmbientPuck(context: &context, cx: cx, cy: cy, active: active, breath: breath)
            drawCenterSafeZone(context: &context, cx: cx, cy: cy)

            if active > 0.02 {
                let tip = activePuckTip(center: CGPoint(x: cx, y: cy))
                drawRay(context: &context, cx: cx, cy: cy, ex: tip.x, ey: tip.y, active: active, full: full)
                drawActivePuck(context: &context, ex: tip.x, ey: tip.y, active: active, full: full)
            }
        }
        .frame(width: RadialPuckMetrics.panelSize.width, height: RadialPuckMetrics.panelSize.height)
        .overlay {
            if activePuckOverlayVisible {
                activeGlyphOverlay
            }
        }
        .overlay(alignment: .topLeading) {
            labelOverlay
        }
    }

    private var activePuckOverlayVisible: Bool {
        renderState.selectionActive > 0.02 && renderState.selection != .none
    }

    @ViewBuilder
    private var activeGlyphOverlay: some View {
        if let action = RadialSelectionMath.action(for: renderState.selection) {
            let tip = activePuckTip(center: center)
            RadialLayoutGlyph(
                kind: RadialLayoutGlyphKind(action: action),
                scale: 0.76 + renderState.selectionActive * 0.10 + renderState.fullScreenBlend * 0.03,
                opacity: renderState.selectionActive
            )
            .position(x: tip.x, y: tip.y)
        }
    }

    private func activePuckTip(center: CGPoint) -> CGPoint {
        let offset = RadialPuckMetrics.activePuckOffset(
            angle: renderState.aimAngle,
            radius: renderState.rayRadius
        )
        return CGPoint(x: center.x + offset.x, y: center.y + offset.y)
    }

    @ViewBuilder
    private var labelOverlay: some View {
        if let text = renderState.labelText, renderState.labelOpacity > 0.01 {
            Text(text)
                .font(.caption.weight(.semibold))
                .foregroundStyle(RadialPuckVisualTokens.labelText)
                .padding(.horizontal, 13)
                .padding(.vertical, 6)
                .background {
                    Capsule(style: .continuous)
                        .fill(RadialPuckVisualTokens.labelPillFill)
                        .overlay {
                            Capsule(style: .continuous)
                                .strokeBorder(RadialPuckVisualTokens.labelPillStroke, lineWidth: 1)
                        }
                }
                .opacity(renderState.labelOpacity)
                .position(x: center.x, y: center.y + RadialPuckMetrics.labelOffsetY)
        }
    }

    private func drawGuideRing(context: inout GraphicsContext, cx: CGFloat, cy: CGFloat, active: CGFloat) {
        let ring = Path(ellipseIn: CGRect(
            x: cx - RadialPuckMetrics.guideRingRadius,
            y: cy - RadialPuckMetrics.guideRingRadius,
            width: RadialPuckMetrics.guideRingRadius * 2,
            height: RadialPuckMetrics.guideRingRadius * 2
        ))
        context.stroke(
            ring,
            with: .color(RadialPuckVisualTokens.hudInk.opacity(RadialPuckVisualTokens.guideRingOpacity(selectionActive: active))),
            lineWidth: 1
        )
    }

    private func drawChevron(context: inout GraphicsContext, cx: CGFloat, cy: CGFloat, full: CGFloat) {
        var path = Path()
        path.move(to: CGPoint(x: cx - 7, y: cy - RadialPuckMetrics.chevronTopY))
        path.addLine(to: CGPoint(x: cx, y: cy - RadialPuckMetrics.chevronApexY))
        path.addLine(to: CGPoint(x: cx + 7, y: cy - RadialPuckMetrics.chevronTopY))
        let opacity = RadialPuckVisualTokens.chevronOpacity(fullScreenBlend: full, isTeaching: showsChevron)
        context.stroke(
            path,
            with: .color(RadialPuckVisualTokens.hudInk.opacity(
                RadialPuckVisualTokens.chevronStrokeOpacity(fullScreenBlend: full) * opacity
            )),
            style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round)
        )
    }

    private func drawAmbientPuck(
        context: inout GraphicsContext,
        cx: CGFloat,
        cy: CGFloat,
        active: CGFloat,
        breath: CGFloat
    ) {
        let baseR = RadialPuckMetrics.ambientPuckRadius + active * 3 + (allowsIdleBreath ? breath * 0.6 : 0)
        let rect = CGRect(x: cx - baseR, y: cy - baseR, width: baseR * 2, height: baseR * 2)
        let puckPath = Path(ellipseIn: rect)
        context.drawLayer { layer in
            layer.addFilter(.shadow(
                color: RadialPuckVisualTokens.ambientPuckShadow,
                radius: 26,
                x: 0,
                y: 14
            ))
            layer.fill(puckPath, with: .color(RadialPuckVisualTokens.ambientPuckFill))
        }
        context.stroke(puckPath, with: .color(RadialPuckVisualTokens.ambientPuckStroke), lineWidth: 1)
    }

    private func drawCenterSafeZone(context: inout GraphicsContext, cx: CGFloat, cy: CGFloat) {
        let dotR = RadialPuckMetrics.centerDotRadius
        context.fill(
            Path(ellipseIn: CGRect(x: cx - dotR, y: cy - dotR, width: dotR * 2, height: dotR * 2)),
            with: .color(RadialPuckVisualTokens.centerDotFill)
        )
        let safeR = RadialPuckMetrics.centerSafeRingRadius
        context.stroke(
            Path(ellipseIn: CGRect(x: cx - safeR, y: cy - safeR, width: safeR * 2, height: safeR * 2)),
            with: .color(RadialPuckVisualTokens.centerSafeRingStroke),
            lineWidth: 1
        )
    }

    private func drawRay(
        context: inout GraphicsContext,
        cx: CGFloat,
        cy: CGFloat,
        ex: CGFloat,
        ey: CGFloat,
        active: CGFloat,
        full: CGFloat
    ) {
        var path = Path()
        path.move(to: CGPoint(x: cx, y: cy))
        path.addLine(to: CGPoint(x: ex, y: ey))
        let tipOpacity = RadialPuckVisualTokens.rayTipOpacity(fullScreenBlend: full)
        let gradient = Gradient(stops: [
            .init(color: RadialPuckVisualTokens.hudInk.opacity(0), location: 0),
            .init(color: RadialPuckVisualTokens.hudInk.opacity(0.14), location: 0.58),
            .init(color: RadialPuckVisualTokens.hudInk.opacity(tipOpacity), location: 1)
        ])
        context.drawLayer { layer in
            layer.opacity = active
            layer.stroke(
                path,
                with: .linearGradient(
                    gradient,
                    startPoint: CGPoint(x: cx, y: cy),
                    endPoint: CGPoint(x: ex, y: ey)
                ),
                style: StrokeStyle(lineWidth: 1.2, lineCap: .round)
            )
        }
    }

    private func drawActivePuck(
        context: inout GraphicsContext,
        ex: CGFloat,
        ey: CGFloat,
        active: CGFloat,
        full: CGFloat
    ) {
        let puckR = RadialPuckMetrics.activePuckRadius + full * RadialPuckMetrics.activePuckFullScreenBoost
        let rect = CGRect(x: ex - puckR, y: ey - puckR, width: puckR * 2, height: puckR * 2)
        let puckPath = Path(ellipseIn: rect)
        context.drawLayer { layer in
            layer.opacity = active
            let shadowColor = full > 0.4
                ? Color.white.opacity(0.16)
                : Color.black.opacity(0.20)
            layer.addFilter(.shadow(color: shadowColor, radius: full > 0.4 ? 20 : 14, x: 0, y: 0))
            layer.fill(puckPath, with: .color(RadialPuckVisualTokens.activePuckFill(fullScreenBlend: full)))
            layer.stroke(
                puckPath,
                with: .color(RadialPuckVisualTokens.activePuckStroke(fullScreenBlend: full)),
                lineWidth: 1
            )
        }
    }
}
