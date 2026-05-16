import FeatureCore
import SwiftUI

/// Shown once after a pre-modular → modular upgrade, courtesy of `Migrator`.
/// Lists each feature's outcome and routes the user to Settings → Features.
struct WhatsNewSheetView: View {
    let report: MigrationReport
    let registry: FeatureRegistry
    let onDismiss: () -> Void
    let onOpenFeaturesSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Mac All You Need is now modular")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("You can pick which features to use. Nothing was disabled — you can change anything in Settings → Features.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 8) {
                ForEach(orderedOutcomes(), id: \.id) { item in
                    if let descriptor = registry.descriptor(for: item.featureID) {
                        FeatureOutcomeRow(descriptor: descriptor, outcome: item.outcome)
                    }
                }
            }

            HStack {
                Spacer()
                MAYNButton("Dismiss", action: onDismiss)
                MAYNButton("Open Features Settings", role: .primary, action: {
                    onOpenFeaturesSettings()
                    onDismiss()
                })
            }
        }
        .padding(24)
        .frame(minWidth: 480, idealWidth: 520)
    }

    private struct OutcomeItem: Identifiable {
        let featureID: FeatureID
        let outcome: MigrationReport.Outcome
        var id: String { featureID.rawValue }
    }

    private func orderedOutcomes() -> [OutcomeItem] {
        registry.descriptors.compactMap { d in
            guard let outcome = report.outcomes[d.id] else { return nil }
            return OutcomeItem(featureID: d.id, outcome: outcome)
        }
    }
}

private struct FeatureOutcomeRow: View {
    let descriptor: FeatureDescriptor
    let outcome: MigrationReport.Outcome

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: descriptor.icon)
                .frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(descriptor.displayName).font(.body)
                Text(statusText).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            StatusPill(text: badgeText, kind: badgeKind)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(MAYNTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var statusText: String {
        switch outcome.assetSource {
        case .preInstallScript:
            return "Kept active — your binaries were carried over from the old version."
        case .versionMismatch:
            return "Needs an update — the binaries from the old version don't match this release."
        case .needsDownload:
            return outcome.resultingState.activationState == .enabled
                ? "Active but needs binaries — install when convenient."
                : "Available — install if you want it back."
        case .notRequired:
            return outcome.resultingState.activationState == .enabled
                ? "Kept active."
                : "Available — enable in Settings → Features."
        }
    }

    private var badgeText: String {
        switch (outcome.assetSource, outcome.resultingState.activationState) {
        case (.versionMismatch, _): return "Update needed"
        case (.needsDownload, _):   return "Install"
        case (_, .enabled):         return "Enabled"
        case (_, .disabled):        return "Disabled"
        }
    }

    private var badgeKind: StatusPill.Kind {
        switch (outcome.assetSource, outcome.resultingState.activationState) {
        case (.versionMismatch, _): return .warning
        case (.needsDownload, _):   return .neutral
        case (_, .enabled):         return .success
        case (_, .disabled):        return .neutral
        }
    }
}
