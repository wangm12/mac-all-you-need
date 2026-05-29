import SwiftUI

struct VoiceCleanupSection: View {
    let cleanupEnabled: Bool
    let cleanupProvider: VoiceCleanupProviderKind
    let cleanupModel: String
    let cleanupBaseURLString: String
    let cleanupTimeoutSeconds: Int
    let cleanupLatencyPolicy: VoiceCleanupLatencyPolicy

    var body: some View {
        MAYNSection(title: "Cleanup") {
            MAYNSettingsRow(
                title: "Cleanup model",
                subtitle: cleanupRowSubtitle,
                belowSubtitle: {
                    AnyView(StatusPill(text: cleanupSavedLine, kind: .neutral))
                }
            ) {
                EmptyView()
            }
        }
    }

    private var cleanupSnapshot: VoiceCleanupSettings {
        VoiceCleanupSettings(
            isEnabled: cleanupEnabled,
            provider: cleanupProvider,
            model: cleanupModel,
            baseURLString: cleanupBaseURLString,
            timeoutSeconds: cleanupTimeoutSeconds,
            latencyPolicy: cleanupLatencyPolicy
        )
    }

    private var cleanupSavedLine: String {
        "\(cleanupProvider.label) · \(cleanupSnapshot.effectiveModel)"
    }

    private var cleanupRowSubtitle: String {
        if cleanupEnabled {
            "Configure details on Voice → Models. Runs after recognition while AI cleanup is on."
        } else {
            "AI cleanup is off; local cleanup and dictionary still apply."
        }
    }
}
