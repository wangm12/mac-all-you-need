import ApplicationServices
import Core
import SwiftUI

struct SnippetsDestinationView: View {
    let controller: AppController
    @AppStorage(SnippetsFunctionTab.storageKey, store: AppGroupSettings.defaults) private var selectedTabRaw = SnippetsFunctionTab.library.rawValue
    @AppStorage(SnippetExpansionSettings.modeKey, store: AppGroupSettings.defaults) private var expansionModeRaw = SnippetExpansionSettings.defaultMode.rawValue

    private var selectedTab: Binding<SnippetsFunctionTab> {
        Binding {
            SnippetsFunctionTab.storedSelection(selectedTabRaw)
        } set: { tab in
            selectedTabRaw = tab.rawValue
        }
    }

    private var expansionMode: SnippetExpansionMode {
        SnippetExpansionMode(rawValue: expansionModeRaw) ?? SnippetExpansionSettings.defaultMode
    }

    var body: some View {
        FunctionPageShell(
            title: "Snippets",
            subtitle: "Reusable text entries and expansion triggers.",
            selection: selectedTab
        ) {
            switch SnippetsFunctionTab.storedSelection(selectedTabRaw) {
            case .library:
                SnippetsListView(model: controller.clipboardDeps.dockModel)
            case .settings:
                FunctionPageScrollContent {
                    snippetsSettingsSection
                }
            }
        }
    }

    private var snippetsSettingsSection: some View {
        MAYNSection(title: "Expansion") {
            MAYNSettingsRow(
                title: SnippetsSettingsPresentation.expansionModeRowTitle,
                subtitle: SnippetsSettingsPresentation.expansionModeSubtitle(for: expansionMode)
            ) {
                FunctionSegmentedTabStrip(
                    tabs: Array(SnippetExpansionMode.allCases),
                    selection: expansionMode,
                    fillsAvailableWidth: false,
                    size: .control
                ) { mode in
                    expansionModeRaw = mode.rawValue
                }
            }
            MAYNDivider()
            MAYNSettingsRow(
                title: SnippetsSettingsPresentation.accessibilityRowTitle,
                subtitle: "Snippet expansion uses the main app Accessibility permission to type into the focused app."
            ) {
                StatusPill(
                    text: AXIsProcessTrusted() ? "Granted" : "Needed",
                    kind: AXIsProcessTrusted() ? .success : .warning
                )
            }
        }
    }
}
