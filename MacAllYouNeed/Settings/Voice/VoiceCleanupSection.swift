import SwiftUI

struct VoiceCleanupSection: View {
    let cleanupEnabled: Bool
    let cleanupProvider: VoiceCleanupProviderKind
    let cleanupModel: String

    var body: some View {
        MAYNSection(title: "Cleanup") {
            MAYNSettingsRow(
                title: "Cleanup model",
                subtitle: cleanupModelSummary
            ) {
                StatusPill(text: cleanupEnabled ? cleanupProvider.label : "Off", kind: .neutral)
            }
        }
    }

    private var cleanupModelSummary: String {
        guard cleanupEnabled else {
            return "AI cleanup is off; local cleanup and dictionary still apply."
        }
        let model = cleanupModel.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.isEmpty ? cleanupProvider.label : "\(cleanupProvider.label) · \(model)"
    }
}
