import SwiftUI

struct WindowGrabOnboardingWizardView: View {
    @State private var statusMessage: String?

    private var dragModifierLabel: String {
        let modifier = WindowControlSettingsStore.load().dragModifier
        if modifier.contains(.option) { return "Option" }
        if modifier.contains(.command) { return "Command" }
        if modifier.contains(.control) { return "Control" }
        if modifier.contains(.shift) { return "Shift" }
        return "Modifier"
    }

    var body: some View {
        FeatureOnboardingPage(
            bullets: [
                "Hold a modifier and drag from any visible window content to move the window.",
                "Ignored-app rules are shared with Window Layouts."
            ],
            previewTitle: "Gesture",
            previewSubtitle: "Drag from content areas — not just the title bar.",
            preview: {
                OnboardingPanel {
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(MAYNTheme.subtleBorder, lineWidth: 1)
                            .frame(width: 120, height: 72)
                            .overlay {
                                VStack(spacing: 4) {
                                    Text("Window")
                                        .font(.caption.weight(.semibold))
                                    Text("Hold \(dragModifierLabel)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        Image(systemName: "hand.draw")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Text("Drag anywhere on content")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            },
            tryItSubtitle: "Move any window using the modifier drag gesture.",
            tryIt: {
            OnboardingTryItPanel(
                instruction: "Hold \(dragModifierLabel) and drag a window from its content area.",
                statusMessage: statusMessage,
                showsConfirm: false
            ) {
                EmptyView()
            }
        },
        footnote: "Change the drag modifier on the Window Grab page."
        )
    }
}
