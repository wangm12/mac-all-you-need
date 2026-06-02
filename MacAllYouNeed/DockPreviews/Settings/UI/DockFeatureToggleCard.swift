import SwiftUI

/// Dashboard-style feature card with a master toggle (Dock Features tab).
struct DockFeatureToggleCard: View {
    let title: String
    let subtitle: String
    let symbolName: String
    var accent: Color = .accentColor
    @Binding var isOn: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbolName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 30, height: 30)
                    .background(accent.opacity(0.10), in: RoundedRectangle(cornerRadius: MAYNControlMetrics.controlRadius, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            Spacer(minLength: 0)

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .accessibilityLabel(title)
        }
        .padding(14)
        .frame(
            maxWidth: .infinity,
            minHeight: DashboardRenderingPresentation.toolCardHeight,
            maxHeight: DashboardRenderingPresentation.toolCardHeight,
            alignment: .topLeading
        )
        .background(cardBackground, in: RoundedRectangle(cornerRadius: MAYNControlMetrics.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: MAYNControlMetrics.cardRadius, style: .continuous)
                .stroke(isOn ? accent.opacity(0.35) : (isHovering ? MAYNTheme.strongBorder : MAYNTheme.subtleBorder), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: MAYNControlMetrics.cardRadius, style: .continuous))
        .onHover { isHovering = $0 }
        .animation(MAYNMotion.hoverAnimation(reduceMotion: reduceMotion), value: isHovering)
        .animation(MAYNMotion.controlAnimation(reduceMotion: reduceMotion), value: isOn)
    }

    private var cardBackground: Color {
        isOn ? MAYNTheme.elevated : MAYNTheme.panel
    }
}
