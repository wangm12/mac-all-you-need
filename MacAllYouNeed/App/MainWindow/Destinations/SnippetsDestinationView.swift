import ApplicationServices
import Core
import Platform
import SwiftUI

struct SnippetsDestinationView: View {
    let controller: AppController
    @AppStorage(SnippetsFunctionTab.storageKey, store: AppGroupSettings.defaults) private var selectedTabRaw = SnippetsFunctionTab.library.rawValue
    @AppStorage(SnippetExpansionSettings.modeKey, store: AppGroupSettings.defaults) private var expansionModeRaw = SnippetExpansionSettings.defaultMode.rawValue
    @State private var hotkeyMap = HotkeyMapStore.defaultMap
    @State private var hotkeyRegistrationErrors: [HotkeyAction: String] = [:]

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
            selection: selectedTab,
            toolbar: {
                MainHeaderShortcutDisplay(
                    text: MainToolHeaderShortcutModel.display(
                        for: .snippets,
                        hotkeys: hotkeyMap,
                        voiceSettings: VoiceActivationSettingsStore.load()
                    )
                )
            }
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
        .onAppear {
            hotkeyMap = HotkeyMapStore.load()
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
            MAYNDivider()
            MAYNSettingsRow(
                title: SnippetsSettingsPresentation.shortcutRowTitle,
                subtitle: "Use the Clipboard shortcut to open the dock, then switch to snippets."
            ) {
                HotkeyRecorderControl(
                    descriptor: hotkeyBinding,
                    issueMessage: hotkeyIssueMessage,
                    candidateIssueMessage: { hotkeyCandidateIssueMessage($0) },
                    defaultDescriptor: HotkeyAction.clipboard.primaryDefaultDescriptor,
                    recorderWidth: 112,
                    errorWidth: 260,
                    reset: {
                        if let descriptor = HotkeyAction.clipboard.primaryDefaultDescriptor {
                            setHotkey(descriptor)
                        }
                    }
                )
            }
        }
    }

    private var hotkeyBinding: Binding<Platform.HotkeyDescriptor> {
        Binding(
            get: {
                let defaultDescriptor = HotkeyAction.clipboard.primaryDefaultDescriptor ?? .defaultClipboard
                let descriptors = hotkeyMap[.clipboard] ?? [defaultDescriptor]
                return descriptors.first ?? defaultDescriptor
            },
            set: { descriptor in
                setHotkey(descriptor)
            }
        )
    }

    private var hotkeyIssueMessage: String? {
        let descriptors = hotkeyMap[.clipboard] ?? HotkeyAction.clipboard.defaultDescriptors
        guard let descriptor = descriptors.first ?? HotkeyAction.clipboard.primaryDefaultDescriptor else {
            return nil
        }
        let validationIssue = HotkeyValidation.issue(
            forAppHotkey: descriptor,
            action: .clipboard,
            index: 0,
            appHotkeys: hotkeyMap,
            voiceShortcut: VoiceActivationSettingsStore.load().shortcut
        )?.message
        return HotkeyRecorderControlPresentation.rowIssueMessage(
            validationIssue: validationIssue,
            registrationErrors: hotkeyRegistrationErrors,
            action: .clipboard
        )
    }

    private func hotkeyCandidateIssueMessage(_ descriptor: Platform.HotkeyDescriptor) -> String? {
        HotkeyValidation.issue(
            forAppHotkey: descriptor,
            action: .clipboard,
            index: 0,
            appHotkeys: hotkeyMap,
            voiceShortcut: VoiceActivationSettingsStore.load().shortcut
        )?.message
    }

    private func setHotkey(_ descriptor: Platform.HotkeyDescriptor) {
        var descriptors = hotkeyMap[.clipboard] ?? HotkeyAction.clipboard.defaultDescriptors
        if descriptors.isEmpty {
            descriptors = [descriptor]
        } else {
            descriptors[0] = descriptor
        }
        var next = hotkeyMap
        next[.clipboard] = descriptors
        autoApplyHotkeys(next)
    }

    private func autoApplyHotkeys(_ next: [HotkeyAction: [Platform.HotkeyDescriptor]]) {
        hotkeyMap = next
        if HotkeyValidation.firstIssue(
            in: next,
            voiceShortcut: VoiceActivationSettingsStore.load().shortcut
        ) != nil {
            hotkeyRegistrationErrors = [:]
            return
        }

        do {
            try controller.applyHotkeyMap(next)
            HotkeyMapStore.save(next)
            hotkeyRegistrationErrors = [:]
        } catch {
            hotkeyRegistrationErrors = HotkeyRecorderControlPresentation.registrationErrors(
                from: error,
                changedAction: .clipboard
            )
        }
    }
}
