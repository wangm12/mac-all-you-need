import FeatureCore
import SwiftUI

struct FeaturePickerCard: View {
    /// Compact picker tile — shorter than dashboard tool cards (no bottom lifecycle row).
    static let uniformHeight: CGFloat = 104

    let descriptor: FeatureDescriptor
    @Binding var isSelected: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    private var tile: DashboardToolTileItem? {
        DashboardToolTilePresentation.primaryTile(for: descriptor.id)
    }

    private var title: String { tile?.title ?? descriptor.displayName }
    private var subtitle: String { tile?.detail ?? descriptor.summary }
    private var symbolName: String { tile?.symbolName ?? descriptor.icon }
    private var accent: Color {
        if let destination = tile?.destination {
            return DashboardToolTilePresentation.accent(for: destination)
        }
        return .accentColor
    }

    private var iconAccent: Color { isSelected ? accent : .secondary }
    private var borderColor: Color {
        if isSelected { return accent.opacity(0.42) }
        if isHovering { return MAYNTheme.strongBorder }
        return MAYNTheme.subtleBorder
    }

    var body: some View {
        Button {
            isSelected.toggle()
        } label: {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: symbolName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(iconAccent)
                    .frame(width: 28, height: 28)
                    .background(iconAccent.opacity(0.10), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isSelected ? .primary : .secondary)
                        .lineLimit(1)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isSelected ? accent : Color.secondary.opacity(0.35))
                    .padding(.top, 2)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, minHeight: Self.uniformHeight, maxHeight: Self.uniformHeight, alignment: .topLeading)
            .background(cardBackground, in: RoundedRectangle(cornerRadius: MAYNControlMetrics.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: MAYNControlMetrics.cardRadius, style: .continuous)
                    .stroke(borderColor, lineWidth: isSelected ? 1.5 : 1)
            }
        }
        .buttonStyle(.plain)
        .opacity(isSelected ? 1 : 0.58)
        .onHover { isHovering = $0 }
        .animation(MAYNMotion.hoverAnimation(reduceMotion: reduceMotion), value: isHovering)
        .animation(MAYNMotion.controlAnimation(reduceMotion: reduceMotion), value: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityLabel("\(title), \(isSelected ? "selected" : "not selected")")
    }

    private var cardBackground: Color {
        if isSelected { return MAYNTheme.elevated }
        return isHovering ? MAYNTheme.panel.opacity(0.92) : MAYNTheme.panel
    }
}
