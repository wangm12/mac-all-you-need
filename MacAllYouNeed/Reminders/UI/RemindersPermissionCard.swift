import SwiftUI

/// Compact EventKit permission prompt used in onboarding / inline surfaces.
struct RemindersPermissionCard: View {
    let onRequest: () async -> Void

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "checklist")
                .foregroundStyle(.secondary)
            Text("Reminders access needed")
                .font(.caption)
                .foregroundStyle(.secondary)
            MAYNButton("Grant Access", role: .primary, height: HotkeyChipPresentation.compactHeight) {
                Task { await onRequest() }
            }
        }
        .padding(8)
    }
}
