import Core
import Platform
import SwiftUI

/// Configuration / guidance page for Finder Folder History, surfaced as the
/// feature's settings tab.
struct FolderHistoryPageView: View {
    @State private var hotkeyMap = HotkeyMapStore.defaultMap

    var body: some View {
        MAYNSettingsPage(
            title: "Finder Folder History",
            subtitle: "Jump back to folders you've opened in Finder via the hotkey or the menu bar."
        ) {
            MAYNSection(title: "How it works") {
                MAYNSettingsRow(
                    title: "Quick switcher",
                    subtitle: "Press the shortcut anywhere to search recent folders and open one."
                ) {
                    HotkeyRecorderControl(
                        descriptor: finderHistoryHotkeyBinding,
                        issueMessage: finderHistoryHotkeyIssueMessage,
                        candidateIssueMessage: finderHistoryHotkeyCandidateIssueMessage,
                        defaultDescriptor: HotkeyAction.finderHistory.primaryDefaultDescriptor,
                        recorderWidth: 112,
                        errorWidth: 260,
                        reset: {
                            if let descriptor = HotkeyAction.finderHistory.primaryDefaultDescriptor {
                                setFinderHistoryHotkey(descriptor)
                            }
                        }
                    )
                }
                MAYNDivider()
                MAYNSettingsRow(
                    title: "Privacy",
                    subtitle: "Only folder paths are recorded — never the contents of any folder."
                ) {
                    EmptyView()
                }
            }
        }
        .onAppear {
            hotkeyMap = HotkeyMapStore.load()
        }
    }

    private var finderHistoryHotkeyBinding: Binding<Platform.HotkeyDescriptor> {
        Binding(
            get: {
                let defaultDescriptor = HotkeyAction.finderHistory.primaryDefaultDescriptor ?? .defaultFolderHistory
                let descriptors = hotkeyMap[.finderHistory] ?? [defaultDescriptor]
                return descriptors.first ?? defaultDescriptor
            },
            set: { setFinderHistoryHotkey($0) }
        )
    }

    private var finderHistoryHotkeyIssueMessage: String? {
        let descriptors = hotkeyMap[.finderHistory] ?? HotkeyAction.finderHistory.defaultDescriptors
        guard let descriptor = descriptors.first ?? HotkeyAction.finderHistory.primaryDefaultDescriptor else {
            return nil
        }
        return HotkeyValidation.issue(
            forAppHotkey: descriptor,
            action: .finderHistory,
            index: 0,
            appHotkeys: hotkeyMap,
            voiceShortcut: VoiceActivationSettingsStore.load().shortcut,
            dockShortcuts: HotkeyValidation.liveDockShortcuts()
        )?.message
    }

    private func finderHistoryHotkeyCandidateIssueMessage(_ descriptor: Platform.HotkeyDescriptor) -> String? {
        HotkeyValidation.issue(
            forAppHotkey: descriptor,
            action: .finderHistory,
            index: 0,
            appHotkeys: hotkeyMap,
            voiceShortcut: VoiceActivationSettingsStore.load().shortcut,
            dockShortcuts: HotkeyValidation.liveDockShortcuts()
        )?.message
    }

    private func setFinderHistoryHotkey(_ descriptor: Platform.HotkeyDescriptor) {
        var descriptors = hotkeyMap[.finderHistory] ?? HotkeyAction.finderHistory.defaultDescriptors
        if descriptors.isEmpty {
            descriptors = [descriptor]
        } else {
            descriptors[0] = descriptor
        }
        var next = hotkeyMap
        next[.finderHistory] = descriptors
        guard HotkeyValidation.firstIssue(
            in: next,
            voiceShortcut: VoiceActivationSettingsStore.load().shortcut,
            dockShortcuts: HotkeyValidation.liveDockShortcuts()
        ) == nil else {
            hotkeyMap = next
            return
        }
        hotkeyMap = next
        HotkeyMapStore.save(next)
        NotificationCenter.default.post(name: .finderHistoryHotkeyDidChange, object: nil)
    }
}

extension Notification.Name {
    static let finderHistoryHotkeyDidChange = Notification.Name("finderHistoryHotkeyDidChange")
}
