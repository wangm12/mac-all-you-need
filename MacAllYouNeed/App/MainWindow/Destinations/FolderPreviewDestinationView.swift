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
            title: "Folder Preview",
            subtitle: "Configure the Finder Space preview for folders and archives.",
            selection: selectedTab,
            toolbar: {
                StatusPill(text: "Quick Look", kind: .neutral)
            }
        ) {
            FunctionPageScrollContent {
                folderSettingsSection
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
}
