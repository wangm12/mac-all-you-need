import SwiftUI

struct DockOnboardingWizardView: View {
    @State private var statusMessage: String?

    private var hub: DockHubSettings {
        DockHubSettingsStore.load()
    }

    var body: some View {
        FeatureOnboardingPage(
            bullets: [
                "Hover Dock icons to preview open windows; enable overlay tooltip to hide native Dock labels.",
                "Use horizontal grid or vertical searchable list switcher; preview-at-original-position highlights the selected window on screen."
            ],
            previewTitle: "Preview",
            previewSubtitle: "Dock hover and window switcher.",
            preview: {
                OnboardingPanel {
                    DockSettingsAnimatedPreview(
                        snapshot: DockSettingsPreviewBuilder.snapshot(hub: hub, context: .dock),
                        context: .dock
                    )
                    .frame(maxWidth: .infinity)
                }
            },
            tryItSubtitle: "Hover any Dock icon to see window previews.",
            tryIt: {
            OnboardingShortcutSection(
                title: "Window switcher",
                subtitle: "Hold this shortcut to cycle windows on the current display.",
                shortcutDisplay: "⌥Tab"
            )

            OnboardingTryItPanel(
                instruction: "Hover an app icon in the Dock until a thumbnail panel appears.",
                statusMessage: statusMessage,
                showsConfirm: false
            ) {
                EmptyView()
            }
        },
        footnote: "Screen Recording improves thumbnails; titles-only mode works without it. Tune layout on the Dock page."
        )
    }
}
