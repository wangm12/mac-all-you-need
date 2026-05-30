import SwiftUI

struct DockPreviewSettingsView: View {
    var body: some View {
        MAYNSettingsPage(
            title: "Dock Previews",
            subtitle: "Hover an app's Dock icon to see thumbnails of its windows. Click a thumbnail to raise that window."
        ) {
            DockPreviewSettingsSection()
        }
    }
}

struct DockPreviewSettingsSection: View {
    @AppStorage("dockPreviews.showThumbnails") private var showThumbnails = true
    @AppStorage("dockPreviews.hoverDelayMS") private var hoverDelayMS = 500

    var body: some View {
        Group {
            MAYNSection(title: "Previews") {
                MAYNSettingsRow(
                    title: "Show window thumbnails",
                    subtitle: "Render a live preview of each window. Requires Screen Recording permission; "
                        + "falls back to a titles-only list when denied."
                ) {
                    Toggle("", isOn: $showThumbnails).labelsHidden()
                }
                MAYNDivider()
                MAYNSettingsRow(
                    title: "Hover delay",
                    subtitle: "How long to hover a Dock icon before the preview appears."
                ) {
                    MAYNNumericStepper(
                        text: "Hover delay",
                        value: $hoverDelayMS,
                        range: 0 ... 2000,
                        step: 50,
                        presets: [250, 500, 1000],
                        suffix: "ms"
                    )
                }
            }
        }
    }
}
