import Core
import SwiftUI

/// Radial pie selector for window-management actions. Eight outer segments map
/// to `RadialMenuLayout.ringActions`; the center represents the center action.
/// Selection highlight and motion route through MAYN tokens only.
struct RadialMenuView: View {
    let actions: [WindowAction]
    let selectedIndex: Int?
    let isCenterSelected: Bool
    var menuRadius: CGFloat = 100

    init(
        actions: [WindowAction],
        selectedIndex: Int?,
        isCenterSelected: Bool = false,
        menuRadius: CGFloat = 100
    ) {
        self.actions = actions
        self.selectedIndex = selectedIndex
        self.isCenterSelected = isCenterSelected
        self.menuRadius = menuRadius
    }

    private var centerDiameter: CGFloat { menuRadius * 0.5 }

    var body: some View {
        ZStack {
            Circle()
                .fill(.regularMaterial)
                .overlay(
                    Circle().strokeBorder(MAYNTheme.subtleBorder, lineWidth: 1)
                )
                .frame(width: menuRadius * 2, height: menuRadius * 2)

            ForEach(actions.indices, id: \.self) { index in
                RadialSegmentShape(index: index, total: actions.count, radius: menuRadius)
                    .fill(selectedIndex == index ? MAYNTheme.focusRing.opacity(0.28) : Color.clear)
            }

            ForEach(actions.indices, id: \.self) { index in
                let angle = (2 * Double.pi / Double(actions.count)) * Double(index) - Double.pi / 2
                let iconX = cos(angle) * menuRadius * 0.7
                let iconY = sin(angle) * menuRadius * 0.7
                Image(systemName: actions[index].symbolName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(selectedIndex == index ? MAYNTheme.focusRing : Color.primary)
                    .offset(x: iconX, y: iconY)
            }

            Circle()
                .fill(isCenterSelected ? MAYNTheme.focusRing.opacity(0.28) : MAYNTheme.selected)
                .frame(width: centerDiameter, height: centerDiameter)
                .overlay(
                    Image(systemName: RadialMenuLayout.centerAction.symbolName)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(isCenterSelected ? MAYNTheme.focusRing : MAYNTheme.muted)
                )
        }
        .frame(width: menuRadius * 2, height: menuRadius * 2)
    }
}

struct RadialSegmentShape: Shape {
    let index: Int
    let total: Int
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let anglePerSegment = 2 * Double.pi / Double(total)
        // Center each wedge on its action direction (top, top-right, ...).
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
