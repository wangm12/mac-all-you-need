import FeatureCore
import SwiftUI

/// Feature-specific onboarding step chrome. Uses the descriptor icon and copy instead of a generic slider header.
struct FeatureOnboardingStepView: View {
    let descriptor: FeatureDescriptor
    var showsHeader = true
    var tryItSucceeded: Binding<Bool>?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if showsHeader {
                featureHeader
            }
            wizardBody
                .environment(\.onboardingTryItSucceeded, tryItSucceeded)
                .environment(\.onboardingRequiresTryIt, descriptor.id != .clipboard)
        }
    }

    private var featureHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: descriptor.icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 36, height: 36)
                .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(MAYNTheme.subtleBorder, lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(descriptor.displayName)
                    .font(.system(size: 20, weight: .semibold))
                Text(descriptor.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var wizardBody: some View {
        if let factory = descriptor.featureOnboardingWizardFactory {
            factory()
        } else if let factory = descriptor.onboardingSetupFactory {
            factory()
        } else {
            Text("No additional setup required.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

/// Reusable highlight row for feature onboarding content.
struct FeatureOnboardingHighlightCard: View {
    let symbol: String
    let title: String
    let detail: String
    var accessory: AnyView?

    init(
        symbol: String,
        title: String,
        detail: String,
        @ViewBuilder accessory: () -> some View = { EmptyView() }
    ) {
        self.symbol = symbol
        self.title = title
        self.detail = detail
        self.accessory = AnyView(accessory())
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 32, height: 32)
                .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: MAYNControlMetrics.controlRadius, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                accessory
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(MAYNTheme.panel, in: RoundedRectangle(cornerRadius: MAYNControlMetrics.panelRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MAYNControlMetrics.panelRadius, style: .continuous)
                .stroke(MAYNTheme.subtleBorder, lineWidth: 1)
        )
    }
}
