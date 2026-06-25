import Core
import SwiftUI

struct FolderPreviewSettingsView: View {
    let controller: AppController
    @AppStorage("folderPreviewIncludeHidden", store: AppGroupSettings.defaults) private var includeHidden = false
    @AppStorage(FolderPreviewSettings.cascadeKey, store: AppGroupSettings.defaults) private var cascade = FolderPreviewSettings.defaultCascadeEnabled
    @AppStorage("folderPreviewMaxEntries", store: AppGroupSettings.defaults) private var maxEntries = 50_000
    var body: some View {
        MAYNSettingsPage(
            title: "Enhanced Finder",
            subtitle: "Tune how much folder and archive content Quick Look indexes before rendering a preview."
        ) {
            MAYNSection(title: "Quick Start") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Open the bundled sample folder to verify the preview experience before you change defaults.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    MAYNButton("Open sample folder", role: .primary) {
                        openSampleFolder()
                    }
                }
            }

            MAYNSection(title: "Enumeration") {
                MAYNSettingsRow(
                    title: "Include hidden files",
                    subtitle: "Show dotfiles and hidden entries in folder previews."
                ) {
                    Toggle("", isOn: $includeHidden)
                        .labelsHidden()
                }
                MAYNDivider()
                MAYNSettingsRow(
                    title: "Cascade folders",
                    subtitle: "Include nested folder contents in previews. Turn off to show only top-level items."
                ) {
                    Toggle("", isOn: $cascade)
                        .labelsHidden()
                }
                MAYNDivider()
                MAYNSettingsRow(
                    title: "Maximum entries",
                    subtitle: "Upper bound for very large folders and archives."
                ) {
                    MAYNNumericStepper(
                        text: "\(maxEntries)",
                        value: $maxEntries,
                        range: 1000...500_000,
                        step: 1000,
                        presets: [1_000, 10_000, 50_000, 100_000, 250_000, 500_000],
                        suffix: "entries",
                        fieldWidth: 78
                    )
                }
            }
        }
    }

    private func openSampleFolder() {
        guard let url = OnboardingSampleResources.folderPreviewSampleURL else { return }
        controller.folder.show(at: url)
    }
}
