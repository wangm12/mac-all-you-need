import SwiftUI

/// Dashboard-style feature card with a master toggle (Dock Features tab).
struct DockFeatureToggleCard: View {
    let title: String
    let subtitle: String
    let symbolName: String
    var accent: Color = .accentColor
    @Binding var isOn: Bool

    var body: some View {
        DashboardFeatureCardShell(
            title: title,
            subtitle: subtitle,
            symbolName: symbolName,
            accent: accent,
            fixedHeight: DashboardRenderingPresentation.toolCardHeight,
            isHighlighted: isOn,
            onHeaderTap: nil,
            middle: { EmptyView() },
            bottom: {
                Toggle("", isOn: $isOn)
                    .labelsHidden()
                    .controlSize(.small)
                    .maynSwitchToggleStyle()
                    .accessibilityLabel(title)
            }
        )
    }
}
