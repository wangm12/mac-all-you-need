import FeatureCore
import SwiftUI

struct OnboardingDoneView: View {
    let registry: FeatureRegistry
    let installedIDs: [FeatureID]
    let skippedIDs: [FeatureID]
    let onDone: () -> Void

    var body: some View {
        SetupTaskPage(
            symbol: "checkmark",
            title: "You're all set",
            subtitle: "Mac All You Need is ready. You can install or remove features any time from Settings → Features."
        ) {
            VStack(alignment: .leading, spacing: 16) {
                if installedIDs.isEmpty && !skippedIDs.isEmpty {
                    StatusPill(text: "No features were enabled", kind: .neutral)
                    Text("Open Settings → Features when you're ready to enable something.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                if !installedIDs.isEmpty {
                    SectionList(
                        title: "Enabled",
                        ids: installedIDs,
                        registry: registry,
                        symbol: "checkmark.circle.fill"
                    )
                }
                if !skippedIDs.isEmpty {
                    SectionList(
                        title: "Skipped",
                        ids: skippedIDs,
                        registry: registry,
                        symbol: "circle"
                    )
                }
            }
        }
    }

    private struct SectionList: View {
        let title: String
        let ids: [FeatureID]
        let registry: FeatureRegistry
        let symbol: String

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.headline)
                ForEach(ids, id: \.self) { id in
                    if let descriptor = registry.descriptor(for: id) {
                        HStack {
                            Image(systemName: symbol).frame(width: 18)
                            Text(descriptor.displayName)
                            Spacer()
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }
}
