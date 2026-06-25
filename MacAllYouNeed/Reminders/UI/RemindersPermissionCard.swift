import SwiftUI

/// Compact EventKit permission prompt used in onboarding / inline surfaces.
struct RemindersPermissionCard: View {
    let onRequest: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "checklist")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Reminders access needed")
                        .font(.callout.weight(.semibold))
                    Text("Allow Mac All You Need to save spoken tasks to Apple Reminders.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            MAYNButton("Grant Access", role: .primary, height: HotkeyChipPresentation.compactHeight) {
                Task { await onRequest() }
            }
        }
        .padding(12)
        .background(MAYNTheme.panel, in: RoundedRectangle(cornerRadius: MAYNControlMetrics.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MAYNControlMetrics.cardRadius, style: .continuous)
                .stroke(MAYNTheme.subtleBorder, lineWidth: 1)
        )
    }
}
