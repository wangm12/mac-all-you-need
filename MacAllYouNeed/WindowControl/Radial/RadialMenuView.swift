import Core
import SwiftUI

/// Hosts the Radial Puck HUD in the menu overlay panel.
struct RadialMenuView: View {
    @ObservedObject var viewModel: RadialMenuViewModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            TimelineView(.animation) { timeline in
                RadialPuckHUDView(
                    renderState: viewModel.tick(
                        now: timeline.date.timeIntervalSinceReferenceDate,
                        reduceMotion: reduceMotion
                    ),
                    showsChevron: viewModel.showsChevron,
                    allowsIdleBreath: viewModel.allowsIdleBreath
                )
            }

            if viewModel.showsFirstUseHint {
                VStack {
                    Spacer()
                    Text(RadialPuckLabelCopy.firstUseHint)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.white.opacity(0.36))
                        .padding(.bottom, 8)
                }
                .allowsHitTesting(false)
            }
        }
        .frame(
            width: RadialPuckMetrics.panelSize.width,
            height: RadialPuckMetrics.panelSize.height
        )
    }
}
