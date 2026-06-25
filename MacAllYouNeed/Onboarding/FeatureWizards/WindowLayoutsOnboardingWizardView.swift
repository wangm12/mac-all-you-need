import SwiftUI

struct WindowLayoutsOnboardingWizardView: View {
    @State private var statusMessage: String?

    private let shortcuts: [(String, String)] = [
        ("Left half", "⌃⌥←"),
        ("Right half", "⌃⌥→"),
        ("Maximize", "⌃⌥↩"),
        ("Center", "⌃⌥C"),
    ]

    var body: some View {
        FeatureOnboardingPage(
            bullets: [
                "Snap the focused window to screen edges, maximize, center, or restore with global shortcuts.",
                "Optional Snap Assist zones, active window borders, and Move to Space shortcuts are in Window Layouts settings."
            ],
            previewTitle: "Layout puck",
            previewSubtitle: "Hold to open the gesture HUD. Pull past the ring for Fill Screen.",
            preview: {
                OnboardingPanel {
                    RadialSettingsPreview()
                        .frame(maxWidth: .infinity)
                }
            },
            tryItSubtitle: "Focus any window, press ⌃⌥← to snap left, then confirm.",
            tryIt: {
            VStack(alignment: .leading, spacing: 14) {
                OnboardingGroupedSection(title: "Default shortcuts", subtitle: nil) {
                    OnboardingPanel {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) {
                            ForEach(shortcuts, id: \.0) { label, keys in
                                HStack {
                                    Text(label)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Spacer(minLength: 0)
                                    ShortcutChip(text: keys, height: HotkeyChipPresentation.compactHeight)
                                }
                            }
                        }
                    }
                }

                OnboardingTryItPanel(
                    instruction: "Try snapping the frontmost window to the left half of your screen.",
                    statusMessage: statusMessage,
                    showsConfirm: false
                ) {
                    EmptyView()
                }
            }
        },
        footnote: "Customize shortcuts, edge snap, and ignored apps on the Window Layouts page."
        )
    }
}
