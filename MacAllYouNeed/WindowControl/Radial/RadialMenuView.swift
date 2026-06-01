import Core
import SwiftUI

/// Radial pie selector for window-management actions. Eight outer segments map
/// to `RadialMenuLayout.ringActions`; the center represents the center action.
/// A top-leading close pill highlights on hover; release, click, Esc, or X dismisses.
struct RadialMenuView: View {
    let actions: [WindowAction]
    let selectedIndex: Int?
    let isCenterSelected: Bool
    var isCloseZoneSelected: Bool = false
    var showsNoTargetWarning: Bool = false
    var showsClosePill: Bool = true
    var menuRadius: CGFloat = RadialMenuMetrics.menuRadius

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        actions: [WindowAction],
        selectedIndex: Int?,
        isCenterSelected: Bool = false,
        isCloseZoneSelected: Bool = false,
        showsNoTargetWarning: Bool = false,
        showsClosePill: Bool = true,
        menuRadius: CGFloat = RadialMenuMetrics.menuRadius
    ) {
        self.actions = actions
        self.selectedIndex = selectedIndex
        self.isCenterSelected = isCenterSelected
        self.isCloseZoneSelected = isCloseZoneSelected
        self.showsNoTargetWarning = showsNoTargetWarning
        self.showsClosePill = showsClosePill
        self.menuRadius = menuRadius
    }

    private var centerButtonRadius: CGFloat { RadialMenuMetrics.centerButtonRadius(for: menuRadius) }
    private var centerDiameter: CGFloat { centerButtonRadius * 2 }
    private var ringIconRadius: CGFloat { RadialMenuMetrics.ringIconRadius(for: menuRadius) }
    private var closePillSize: CGSize { RadialMenuMetrics.closePillSize }
    private var panelLayout: RadialMenuMetrics.PanelLayout {
        RadialMenuMetrics.panelLayout(for: menuRadius, showsClosePill: showsClosePill)
    }
    private var ringIconFontSize: CGFloat { max(11, menuRadius * 0.14) }
    private var centerIconFont: Font { menuRadius >= RadialMenuMetrics.menuRadius * 0.9 ? .body.weight(.medium) : .callout.weight(.medium) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ZStack {
                Circle()
                    .fill(.regularMaterial)
                    .frame(width: menuRadius * 2, height: menuRadius * 2)

                ForEach(actions.indices, id: \.self) { index in
                    RadialSegmentShape(index: index, total: actions.count, radius: menuRadius)
                        .fill(selectedIndex == index ? MAYNTheme.focusRing.opacity(0.28) : Color.clear)
                }

                ForEach(actions.indices, id: \.self) { index in
                    let angle = (2 * Double.pi / Double(actions.count)) * Double(index) - Double.pi / 2
                    let iconX = cos(angle) * ringIconRadius
                    let iconY = sin(angle) * ringIconRadius
                    Image(systemName: actions[index].symbolName)
                        .font(.system(size: ringIconFontSize, weight: .medium))
                        .foregroundStyle(selectedIndex == index ? MAYNTheme.focusRing : Color.primary)
                        .offset(x: iconX, y: iconY)
                }

                Circle()
                    .fill(radialHubTint(isSelected: isCenterSelected))
                    .frame(width: centerDiameter, height: centerDiameter)
                    .overlay {
                        if showsNoTargetWarning {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(centerIconFont)
                                .foregroundStyle(MAYNTheme.warning)
                        } else {
                            Image(systemName: RadialMenuLayout.centerAction.symbolName)
                                .font(centerIconFont)
                                .foregroundStyle(radialHubIconColor(isSelected: isCenterSelected))
                        }
                    }
            }
            .frame(width: menuRadius * 2, height: menuRadius * 2)
            .position(x: panelLayout.circleCenter.x, y: panelLayout.circleCenter.y)

            if showsClosePill {
                closePill
                    .position(
                        x: panelLayout.closePillOrigin.x + closePillSize.width / 2,
                        y: panelLayout.closePillOrigin.y + closePillSize.height / 2
                    )
            }
        }
        .frame(width: panelLayout.size.width, height: panelLayout.size.height)
    }

    private var closePill: some View {
        ZStack {
            Capsule(style: .continuous)
                .fill(radialHubTint(isSelected: isCloseZoneSelected))
            Image(systemName: "xmark")
                .font(centerIconFont)
                .foregroundStyle(radialHubIconColor(isSelected: isCloseZoneSelected))
        }
        .frame(width: closePillSize.width, height: closePillSize.height)
        .background(.regularMaterial, in: Capsule(style: .continuous))
        .animation(MAYNMotion.fastAnimation(reduceMotion: reduceMotion), value: isCloseZoneSelected)
        .accessibilityLabel("Close radial menu")
    }

    /// Shared hub chrome for the center maximize control and the close pill.
    private func radialHubTint(isSelected: Bool) -> Color {
        isSelected ? MAYNTheme.focusRing.opacity(0.28) : MAYNTheme.selected
    }

    private func radialHubIconColor(isSelected: Bool) -> Color {
        isSelected ? MAYNTheme.focusRing : MAYNTheme.muted
    }
}

struct RadialSegmentShape: Shape {
    let index: Int
    let total: Int
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let anglePerSegment = 2 * Double.pi / Double(total)
        let startAngle = anglePerSegment * Double(index) - Double.pi / 2 - anglePerSegment / 2
        let endAngle = startAngle + anglePerSegment
        var path = Path()
        path.move(to: center)
        path.addArc(
            center: center,
            radius: radius,
            startAngle: Angle(radians: startAngle),
            endAngle: Angle(radians: endAngle),
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}
