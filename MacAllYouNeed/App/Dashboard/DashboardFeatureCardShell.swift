import SwiftUI

/// Shared dashboard / Dock Features card chrome: header, optional middle content, bottom control row.
struct DashboardFeatureCardShell<Middle: View, Bottom: View, HeaderTrailing: View>: View {
    let title: String
    let subtitle: String
    let symbolName: String
    var accent: Color = .accentColor
    let fixedHeight: CGFloat
    var isHighlighted: Bool = false
    var onHeaderTap: (() -> Void)?
    @ViewBuilder let headerTrailing: () -> HeaderTrailing
    @ViewBuilder let middle: () -> Middle
    @ViewBuilder let bottom: () -> Bottom

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, 14)

            middle()

            Spacer(minLength: 8)

            bottom()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .frame(
            maxWidth: .infinity,
            minHeight: fixedHeight,
            maxHeight: fixedHeight,
            alignment: .topLeading
        )
        .background(cardBackground, in: RoundedRectangle(cornerRadius: MAYNControlMetrics.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: MAYNControlMetrics.cardRadius, style: .continuous)
                .stroke(
                    isHighlighted ? accent.opacity(0.35) : (isHovering ? MAYNTheme.strongBorder : MAYNTheme.subtleBorder),
                    lineWidth: 1
                )
        }
        .contentShape(RoundedRectangle(cornerRadius: MAYNControlMetrics.cardRadius, style: .continuous))
        .onHover { isHovering = $0 }
        .animation(MAYNMotion.hoverAnimation(reduceMotion: reduceMotion), value: isHovering)
        .animation(MAYNMotion.controlAnimation(reduceMotion: reduceMotion), value: isHighlighted)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                onHeaderTap?()
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: symbolName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(accent)
                        .frame(width: 30, height: 30)
                        .background(
                            accent.opacity(0.10),
                            in: RoundedRectangle(
                                cornerRadius: MAYNControlMetrics.controlRadius,
                                style: .continuous
                            )
                        )

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
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .disabled(onHeaderTap == nil)

            headerTrailing()
        }
    }

    private var cardBackground: Color {
        isHighlighted ? MAYNTheme.elevated : MAYNTheme.panel
    }
}
