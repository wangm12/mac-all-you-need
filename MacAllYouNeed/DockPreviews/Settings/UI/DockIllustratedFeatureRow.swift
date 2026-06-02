import SwiftUI

enum DockHeroArt {
    case dockPreviews
    case windowSwitcher
    case cmdTab
    case dockLocking
    case activeIndicator
}

/// Toggle row with a looping animated demo (DockDoor `SettingsIllustratedToggle` layout).
struct DockIllustratedFeatureRow: View {
    let title: String
    let subtitle: String
    let hero: DockHeroArt
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Toggle(isOn: $isOn) {
                    Text(title)
                        .font(.callout.weight(.medium))
                }

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 20)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            DockHeroAnimatedDemo(art: hero)
                .frame(width: 168, height: 104)
        }
        .padding(.horizontal, MAYNControlMetrics.rowHorizontalPadding)
        .padding(.vertical, 14)
    }
}
