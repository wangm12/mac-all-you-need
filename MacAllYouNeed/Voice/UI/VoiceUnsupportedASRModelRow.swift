import SwiftUI

struct VoiceUnsupportedASRModelRow: View {
    let descriptor: VoiceModelDescriptor
    var statusText: String = "Unavailable"

    var body: some View {
        MAYNSettingsRow(
            title: descriptor.title,
            subtitle: descriptor.subtitle
        ) {
            HStack(spacing: 8) {
                if let requiresOSLabel = descriptor.requiresOSLabel {
                    StatusPill(text: requiresOSLabel, kind: .neutral)
                }
                StatusPill(text: statusText, kind: .warning)
            }
        }
    }
}

struct VoiceUnsupportedASRModelCard: View {
    let descriptor: VoiceModelDescriptor
    var statusText: String = "Unavailable"

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(descriptor.title)
                    .font(.headline)
                Spacer()
                Image(systemName: "circle")
                    .foregroundStyle(.secondary)
            }
            Text(descriptor.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                if let requiresOSLabel = descriptor.requiresOSLabel {
                    StatusPill(text: requiresOSLabel, kind: .neutral)
                }
                StatusPill(text: statusText, kind: .warning)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MAYNTheme.panel)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(MAYNTheme.subtleBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
