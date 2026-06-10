import SwiftUI

/// Section header + content block for feature onboarding wizards.
struct OnboardingGroupedSection<Content: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            content()
        }
    }
}

/// Panel wrapper used inside onboarding sections.
struct OnboardingPanel<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MAYNTheme.panel, in: RoundedRectangle(cornerRadius: MAYNControlMetrics.panelRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: MAYNControlMetrics.panelRadius, style: .continuous)
                    .stroke(MAYNTheme.subtleBorder, lineWidth: 1)
            )
    }
}
