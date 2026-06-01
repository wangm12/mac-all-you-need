import Core
import Platform
import SwiftUI

struct ShortcutsSettingsView: View {
    @Bindable var registry: ShortcutRegistry
    @AppStorage(SnippetExpansionSettings.modeKey, store: AppGroupSettings.defaults) private var expansionModeRaw = SnippetExpansionSettings.defaultMode.rawValue
    @State private var pendingError: String?
    @State private var issueAction: ShortcutAction?
    /// Chip preview for the in-row recorder (cleared after each successful add).
    @State private var capturePreviewByAction: [ShortcutAction: HotkeyDescriptor] = [:]

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
                    dockShortcutRow(action: action)

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

    @ViewBuilder
    private func dockShortcutRow(action: ShortcutAction) -> some View {
        let bindings = registry.bindings(for: action)
        let defaultDescriptor = ShortcutDefaults.defaultBindings(for: action).first
            ?? HotkeyDescriptor(keyCode: 0, modifiers: [])

        MAYNSettingsRow(
            title: action.label,
            subtitle: "Capture a key combination, double-tap a modifier, or reset to the default binding.",
            minHeight: 58
        ) {
            VStack(alignment: .trailing, spacing: 8) {
                HStack(spacing: 6) {
                    ForEach(Array(bindings.enumerated()), id: \.offset) { _, binding in
                        ShortcutChip(
                            text: HotkeyChipPresentation.displayText(binding.display),
                            height: HotkeyChipPresentation.compactHeight
                        )
                            .contextMenu {
                                Button("Remove") {
                                    registry.removeBinding(binding, for: action)
                                }
                            }
                    }
                }

                HStack(spacing: 8) {
                    HotkeyRecorderControl(
                        descriptor: captureBinding(for: action),
                        issueMessage: issueAction == action ? pendingError : nil,
                        candidateIssueMessage: { candidateIssueMessage($0, for: action) },
                        defaultDescriptor: defaultDescriptor,
                        recorderWidth: 130,
                        reset: {
                            capturePreviewByAction[action] = nil
                            registry.reset(action: action)
                        }
                    )
                }
            }
        }
    }

    private func captureBinding(for action: ShortcutAction) -> Binding<HotkeyDescriptor> {
        Binding {
            capturePreviewByAction[action] ?? HotkeyDescriptor(keyCode: 0, modifiers: [])
        } set: { newValue in
            guard newValue.isModifierTap || newValue.keyCode != 0 || !newValue.modifiers.isEmpty else { return }
            issueAction = action
            do {
                try registry.validate(newValue, for: action)
                registry.addBinding(newValue, for: action)
                capturePreviewByAction[action] = newValue
                pendingError = nil
                issueAction = nil
            } catch let error as ShortcutValidationError {
                switch error {
                case .validation(let message):
                    pendingError = message
                case .reservedKey:
                    pendingError = "Cannot bind reserved key."
                }
            } catch {
                pendingError = "Cannot bind reserved key."
            }
        }
    }

    private func candidateIssueMessage(_ descriptor: HotkeyDescriptor, for action: ShortcutAction) -> String? {
        HotkeyValidation.issue(
            forDockShortcut: descriptor,
            action: action,
            index: registry.bindings(for: action).count,
            dockShortcuts: registry.allBindings()
        )?.message
    }
}
