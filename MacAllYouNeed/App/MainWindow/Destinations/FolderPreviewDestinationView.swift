import Core
import SwiftUI

struct FolderPreviewDestinationView: View {
    let controller: AppController
    @AppStorage("folderPreviewIncludeHidden", store: AppGroupSettings.defaults) private var includeHidden = false
    @AppStorage(FolderPreviewSettings.cascadeKey, store: AppGroupSettings.defaults) private var cascade = FolderPreviewSettings.defaultCascadeEnabled
    @AppStorage("folderPreviewMaxEntries", store: AppGroupSettings.defaults) private var maxEntries = 50_000
    @AppStorage(FolderPreviewFunctionTab.storageKey, store: AppGroupSettings.defaults) private var selectedTabRaw = FolderPreviewFunctionTab.settings.rawValue

    private var selectedTab: Binding<FolderPreviewFunctionTab> {
        Binding {
            FolderPreviewFunctionTab.storedSelection(selectedTabRaw)
        } set: { tab in
            selectedTabRaw = tab.rawValue
        }
    }

    var body: some View {
        FunctionPageShell(
            title: "Enhanced Finder",
            subtitle: "Quick Look previews, browse folder, and Finder visit history.",
            selection: selectedTab
        ) {
            switch FolderPreviewFunctionTab.storedSelection(selectedTabRaw) {
            case .settings:
                FunctionPageScrollContent {
                    starterSection
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Browse folders and revisit history")
                            .font(.headline.weight(.semibold))
                        Text("Use Preview for folder defaults and History for recent Finder locations. The menu bar popover shows the live shortcut list.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    folderSettingsSection
                }
            case .history:
                FolderHistoryPageView(embeddedInFinderPreview: true)
            }
        }
    }

    private var starterSection: some View {
        MAYNSection(title: "Start Here") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Open a sample folder to see the preview flow immediately, then tune the defaults below.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    MAYNButton("Open sample folder", role: .primary) {
                        openSampleFolder()
                    }
                    MAYNButton("Open settings", role: .secondary) {
                        selectedTabRaw = FolderPreviewFunctionTab.settings.rawValue
                    }
                }
            }
        }
    }

    private var folderSettingsSection: some View {
        MAYNSection(title: FolderPreviewMainPagePresentation.settingsSectionTitle) {
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

    private func openSampleFolder() {
        guard let url = OnboardingSampleResources.folderPreviewSampleURL else { return }
        controller.folder.show(at: url)
    }
}
