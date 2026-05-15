import Platform
import SwiftUI

struct HotkeysSettingsView: View {
    let controller: AppController
    @State private var map: [HotkeyAction: [HotkeyDescriptor]]
    @State private var errorMessage: String?

    init(controller: AppController) {
        self.controller = controller
        _map = State(initialValue: HotkeyMapStore.load())
    }

    var body: some View {
        MAYNSettingsPage(
            title: "Hotkeys",
            subtitle: "Set global keyboard triggers for app-wide commands."
        ) {
            MAYNSection(title: "Global triggers") {
                ForEach(Array(HotkeyAction.allCases.enumerated()), id: \.element.id) { offset, action in
                    let descriptors = map[action] ?? [action.defaultDescriptor]
                    MAYNSettingsRow(
                        title: action.label,
                        subtitle: "Add up to three trigger combinations.",
                        minHeight: descriptors.count > 1 ? 46 + CGFloat(descriptors.count - 1) * 32 : 46
                    ) {
                        VStack(alignment: .trailing, spacing: 8) {
                            HStack(alignment: .top, spacing: 8) {
                                HotkeyRecorderControl(
                                    descriptor: binding(for: action, index: 0, defaultValue: action.defaultDescriptor),
                                    issueMessage: issueMessage(for: action, index: 0),
                                    defaultDescriptor: action.defaultDescriptor,
                                    recorderWidth: 112,
                                    errorWidth: 240,
                                    alignment: .trailing,
                                    errorFrameAlignment: .trailing,
                                    reset: { setDescriptor(action.defaultDescriptor, for: action, index: 0) }
                                )
                                Button {
                                    var updated = descriptors
                                    guard updated.count < 3 else { return }
                                    updated.append(action.defaultDescriptor)
                                    var next = map
                                    next[action] = updated
                                    map = next
                                    errorMessage = "Record a unique shortcut for the new \(action.label) trigger."
                                } label: {
                                    Image(systemName: "plus.circle")
                                }
                                .buttonStyle(.plain)
                                .help("Add another trigger")
                            }

                            ForEach(Array(descriptors.dropFirst().enumerated()), id: \.offset) { offset, _ in
                                let index = offset + 1
                                HStack(alignment: .top, spacing: 8) {
                                    HotkeyRecorderControl(
                                        descriptor: binding(for: action, index: index, defaultValue: action.defaultDescriptor),
                                        issueMessage: issueMessage(for: action, index: index),
                                        defaultDescriptor: action.defaultDescriptor,
                                        recorderWidth: 112,
                                        errorWidth: 240,
                                        alignment: .trailing,
                                        errorFrameAlignment: .trailing,
                                        reset: { setDescriptor(action.defaultDescriptor, for: action, index: index) }
                                    )
                                    Button {
                                        var updated = descriptors
                                        updated.remove(at: index)
                                        var next = map
                                        next[action] = updated.isEmpty ? [action.defaultDescriptor] : updated
                                        autoApply(next)
                                    } label: {
                                        Image(systemName: "delete.left")
                                    }
                                    .buttonStyle(.plain)
                                    .help("Remove trigger")
                                }
                            }
                        }
                    }

                    if offset != HotkeyAction.allCases.count - 1 {
                        MAYNDivider()
                    }
                }
            }

            if let errorMessage {
                MAYNSection(title: "Status") {
                    MAYNSettingsRow(title: "Hotkey status") {
                        StatusPill(text: errorMessage, kind: .danger)
                    }
                }
            }
        }
    }

    private func binding(for action: HotkeyAction, index: Int, defaultValue: HotkeyDescriptor) -> Binding<HotkeyDescriptor> {
        Binding(
            get: {
                let descriptors = map[action] ?? [defaultValue]
                if descriptors.indices.contains(index) {
                    return descriptors[index]
                }
                return defaultValue
            },
            set: { newValue in
                setDescriptor(newValue, for: action, index: index)
            }
        )
    }

    private func setDescriptor(_ descriptor: HotkeyDescriptor, for action: HotkeyAction, index: Int) {
        var descriptors = map[action] ?? [action.defaultDescriptor]
        while descriptors.count <= index {
            descriptors.append(action.defaultDescriptor)
        }
        descriptors[index] = descriptor
        var next = map
        next[action] = descriptors
        autoApply(next)
    }

    private func issueMessage(for action: HotkeyAction, index: Int) -> String? {
        let descriptors = map[action] ?? [action.defaultDescriptor]
        guard descriptors.indices.contains(index) else { return nil }
        return HotkeyValidation.issue(
            forAppHotkey: descriptors[index],
            action: action,
            index: index,
            appHotkeys: map,
            voiceShortcut: VoiceActivationSettingsStore.load().shortcut
        )?.message
    }

    private func autoApply(_ updatedMap: [HotkeyAction: [HotkeyDescriptor]]) {
        map = updatedMap
        if let issue = HotkeyValidation.firstIssue(
            in: updatedMap,
            voiceShortcut: VoiceActivationSettingsStore.load().shortcut
        ) {
            errorMessage = issue.message
            return
        }

        do {
            try controller.applyHotkeyMap(updatedMap)
            HotkeyMapStore.save(updatedMap)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
