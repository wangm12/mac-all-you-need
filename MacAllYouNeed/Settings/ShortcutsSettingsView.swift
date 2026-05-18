import Core
import SwiftUI

struct ShortcutsSettingsView: View {
    @Bindable var registry: ShortcutRegistry
    @AppStorage(SnippetExpansionSettings.modeKey, store: AppGroupSettings.defaults) private var expansionModeRaw = SnippetExpansionSettings.defaultMode.rawValue
    @State private var pendingError: String?

    private var expansionMode: SnippetExpansionMode {
        SnippetExpansionMode(rawValue: expansionModeRaw) ?? SnippetExpansionSettings.defaultMode
    }

    var body: some View {
        MAYNSettingsPage(
            title: "Snippets",
            subtitle: "Configure expansion behavior and shortcuts used inside the clipboard dock."
        ) {
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
            }

            MAYNSection(title: "In-dock shortcuts") {
                ForEach(Array(ShortcutAction.allCases.enumerated()), id: \.element.id) { offset, action in
                    MAYNSettingsRow(
                        title: action.label,
                        subtitle: "Capture a key combination or reset to the default binding.",
                        minHeight: 58
                    ) {
                        VStack(alignment: .trailing, spacing: 8) {
                            HStack(spacing: 6) {
                                ForEach(registry.bindings(for: action), id: \.self) { binding in
                                    ShortcutChip(text: binding.display(), height: HotkeyChipPresentation.compactHeight)
                                        .contextMenu {
                                            Button("Remove") {
                                                registry.removeBinding(binding, for: action)
                                            }
                                        }
                                }
                            }

                            HStack(spacing: 8) {
                                ShortcutRecorderView(binding: .constant(nil)) { captured in
                                    do {
                                        try registry.validate(captured, for: action)
                                        registry.addBinding(captured, for: action)
                                        pendingError = nil
                                    } catch {
                                        pendingError = "Cannot bind reserved key."
                                    }
                                }
                                .frame(width: 130, height: HotkeyChipPresentation.compactHeight)

                                MAYNButton("Reset", height: HotkeyChipPresentation.compactHeight) {
                                    registry.reset(action: action)
                                }
                            }
                        }
                    }

                    if offset != ShortcutAction.allCases.count - 1 {
                        MAYNDivider()
                    }
                }
            }

            if let pendingError {
                MAYNSection(title: "Status") {
                    MAYNSettingsRow(title: "Shortcut error") {
                        StatusPill(text: pendingError, kind: .danger)
                    }
                }
            }
        }
    }
}
