import Carbon.HIToolbox
import FeatureCore
import Platform
import SwiftUI

// Platform.HotkeyDescriptor (keyCode+modifiers) takes precedence in this file.
private typealias HotkeyDescriptor = Platform.HotkeyDescriptor

struct HotkeysSettingsActionGroup: Identifiable, Equatable {
    let title: String
    let actions: [HotkeyAction]

    var id: String { title }
}

enum HotkeysSettingsPresentation {
    static let customTriggerSeedDescriptor = Platform.HotkeyDescriptor(
        keyCode: UInt32(kVK_ANSI_A),
        modifiers: [.control, .option, .shift]
    )

    static let groups: [HotkeysSettingsActionGroup] = [
        HotkeysSettingsActionGroup(title: "Core tools", actions: [.clipboard, .browseFolder, .finderHistory]),
        HotkeysSettingsActionGroup(title: "Window Layouts", actions: [
            .windowLeftHalf,
            .windowRightHalf,
            .windowTopHalf,
            .windowBottomHalf,
            .windowTopLeft,
            .windowTopRight,
            .windowBottomLeft,
            .windowBottomRight,
            .windowMaximize,
            .windowAlmostMaximize,
            .windowCenter,
            .windowRestore,
            .windowNextDisplay,
            .windowPreviousDisplay
        ])
    ]

    static func canAddTrigger(to descriptors: [Platform.HotkeyDescriptor]) -> Bool {
        descriptors.count < 3
    }

    static func displayedDescriptors(
        stored: [Platform.HotkeyDescriptor],
        pending: [Platform.HotkeyDescriptor]
    ) -> [Platform.HotkeyDescriptor] {
        let remaining = max(0, 3 - stored.count)
        return stored + Array(pending.prefix(remaining))
    }

    static func pendingDescriptorsAfterAdding(
        action: HotkeyAction,
        storedDescriptors: [Platform.HotkeyDescriptor],
        pendingDescriptors: [Platform.HotkeyDescriptor]
    ) -> [Platform.HotkeyDescriptor] {
        guard pendingDescriptors.isEmpty else { return pendingDescriptors }
        let displayed = displayedDescriptors(stored: storedDescriptors, pending: pendingDescriptors)
        guard canAddTrigger(to: displayed) else { return pendingDescriptors }
        return pendingDescriptors + [seedDescriptor(for: action)]
    }

    static func seedDescriptor(for action: HotkeyAction) -> Platform.HotkeyDescriptor {
        action.primaryDefaultDescriptor ?? customTriggerSeedDescriptor
    }

    static func descriptorsAfterRemoving(
        index: Int,
        from descriptors: [Platform.HotkeyDescriptor]
    ) -> [Platform.HotkeyDescriptor] {
        guard descriptors.indices.contains(index) else { return descriptors }
        var updated = descriptors
        updated.remove(at: index)
        return updated
    }

    static func resetDescriptor(
        for action: HotkeyAction,
        current descriptor: Platform.HotkeyDescriptor
    ) -> Platform.HotkeyDescriptor? {
        action.primaryDefaultDescriptor ?? descriptor
    }
}

struct HotkeysSettingsView: View {
    let controller: AppController
    private var statePublisher: FeatureStatePublisher
    @State private var map: [HotkeyAction: [HotkeyDescriptor]]
    @State private var pendingTriggerDescriptors: [HotkeyAction: [HotkeyDescriptor]] = [:]
    @State private var errorMessage: String?

    init(controller: AppController) {
        self.controller = controller
        self.statePublisher = controller.featureStatePublisher
        _map = State(initialValue: HotkeyMapStore.load())
    }

    var body: some View {
        MAYNSettingsPage(
            title: "Hotkeys",
            subtitle: "Set global keyboard triggers for app-wide commands."
        ) {
            ForEach(HotkeysSettingsPresentation.groups) { group in
                MAYNSection(title: group.title) {
                    ForEach(Array(group.actions.enumerated()), id: \.element.id) { offset, action in
                        let storedDescriptors = storedDescriptors(for: action)
                        let pendingDescriptors = pendingTriggerDescriptors[action] ?? []
                        let descriptors = HotkeysSettingsPresentation.displayedDescriptors(
                            stored: storedDescriptors,
                            pending: pendingDescriptors
                        )
                        let featureEnabled = isEnabled(action: action)
                        MAYNSettingsRow(
                            title: action.label,
                            subtitle: featureEnabled
                                ? "Add up to three trigger combinations."
                                : "Feature is disabled - hotkey inactive.",
                            minHeight: descriptors.count > 1 ? 46 + CGFloat(descriptors.count - 1) * 32 : 46
                        ) {
                            VStack(alignment: .trailing, spacing: 8) {
                                if descriptors.isEmpty {
                                    HStack(alignment: .center, spacing: 8) {
                                        StatusPill(text: "Off", kind: .neutral)
                                        Button {
                                            addTrigger(
                                                for: action,
                                                storedDescriptors: storedDescriptors,
                                                pendingDescriptors: pendingDescriptors
                                            )
                                        } label: {
                                            Image(systemName: "plus.circle")
                                        }
                                        .buttonStyle(.plain)
                                        .help("Add trigger")
                                    }
                                } else {
                                    HStack(alignment: .top, spacing: 8) {
                                        HotkeyRecorderControl(
                                            descriptor: binding(for: action, index: 0, defaultValue: descriptors[0]),
                                            issueMessage: issueMessage(for: action, index: 0),
                                            candidateIssueMessage: { candidateIssueMessage($0, for: action, index: 0) },
                                            defaultDescriptor: HotkeysSettingsPresentation.resetDescriptor(
                                                for: action,
                                                current: descriptors[0]
                                            ),
                                            recorderWidth: 112,
                                            errorWidth: 240,
                                            alignment: .trailing,
                                            errorFrameAlignment: .trailing,
                                            reset: {
                                                if let defaultDescriptor = action.primaryDefaultDescriptor {
                                                    setDescriptor(defaultDescriptor, for: action, index: 0)
                                                }
                                            }
                                        )
                                        if HotkeysSettingsPresentation.canAddTrigger(to: descriptors) {
                                            Button {
                                                addTrigger(
                                                    for: action,
                                                    storedDescriptors: storedDescriptors,
                                                    pendingDescriptors: pendingDescriptors
                                                )
                                            } label: {
                                                Image(systemName: "plus.circle")
                                            }
                                            .buttonStyle(.plain)
                                            .help("Add another trigger")
                                        }
                                        Button {
                                            removeTrigger(
                                                for: action,
                                                storedDescriptors: storedDescriptors,
                                                pendingDescriptors: pendingDescriptors,
                                                index: 0
                                            )
                                        } label: {
                                            Image(systemName: "delete.left")
                                        }
                                        .buttonStyle(.plain)
                                        .help(descriptors.count == 1 ? "Turn off trigger" : "Remove trigger")
                                    }

                                    ForEach(Array(descriptors.dropFirst().enumerated()), id: \.offset) { offset, _ in
                                        let index = offset + 1
                                        HStack(alignment: .top, spacing: 8) {
                                            HotkeyRecorderControl(
                                                descriptor: binding(for: action, index: index, defaultValue: descriptors[index]),
                                                issueMessage: issueMessage(for: action, index: index),
                                                candidateIssueMessage: { candidateIssueMessage($0, for: action, index: index) },
                                                defaultDescriptor: HotkeysSettingsPresentation.resetDescriptor(
                                                    for: action,
                                                    current: descriptors[index]
                                                ),
                                                recorderWidth: 112,
                                                errorWidth: 240,
                                                alignment: .trailing,
                                                errorFrameAlignment: .trailing,
                                                reset: {
                                                    if let defaultDescriptor = action.primaryDefaultDescriptor {
                                                        setDescriptor(defaultDescriptor, for: action, index: index)
                                                    }
                                                }
                                            )
                                            Button {
                                                removeTrigger(
                                                    for: action,
                                                    storedDescriptors: storedDescriptors,
                                                    pendingDescriptors: pendingDescriptors,
                                                    index: index
                                                )
                                            } label: {
                                                Image(systemName: "delete.left")
                                            }
                                            .buttonStyle(.plain)
                                            .help("Remove trigger")
                                        }
                                    }
                                }
                            }
                        }
                        .opacity(featureEnabled ? 1.0 : 0.45)

                        if offset != group.actions.count - 1 {
                            MAYNDivider()
                        }
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

    private func isEnabled(action: HotkeyAction) -> Bool {
        guard let featureID = action.relatedFeatureID else { return true }
        return statePublisher.state(for: featureID).activationState == .enabled
    }

    private func storedDescriptors(for action: HotkeyAction) -> [HotkeyDescriptor] {
        map[action] ?? action.defaultDescriptors
    }

    private func binding(for action: HotkeyAction, index: Int, defaultValue: HotkeyDescriptor) -> Binding<HotkeyDescriptor> {
        Binding(
            get: {
                let descriptors = HotkeysSettingsPresentation.displayedDescriptors(
                    stored: storedDescriptors(for: action),
                    pending: pendingTriggerDescriptors[action] ?? []
                )
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
        var descriptors = storedDescriptors(for: action)
        let storedCount = descriptors.count
        while descriptors.count <= index {
            descriptors.append(action.primaryDefaultDescriptor ?? descriptor)
        }
        descriptors[index] = descriptor
        if index >= storedCount {
            var pending = pendingTriggerDescriptors[action] ?? []
            let pendingIndex = index - storedCount
            if pending.indices.contains(pendingIndex) {
                pending.remove(at: pendingIndex)
            }
            pendingTriggerDescriptors[action] = pending.isEmpty ? nil : pending
        }
        var next = map
        next[action] = descriptors
        autoApply(next)
    }

    private func addTrigger(
        for action: HotkeyAction,
        storedDescriptors: [HotkeyDescriptor],
        pendingDescriptors: [HotkeyDescriptor]
    ) {
        let pending = HotkeysSettingsPresentation.pendingDescriptorsAfterAdding(
            action: action,
            storedDescriptors: storedDescriptors,
            pendingDescriptors: pendingDescriptors
        )
        pendingTriggerDescriptors[action] = pending
        errorMessage = "Record a unique shortcut for the new \(action.label) trigger."
    }

    private func removeTrigger(
        for action: HotkeyAction,
        storedDescriptors: [HotkeyDescriptor],
        pendingDescriptors: [HotkeyDescriptor],
        index: Int
    ) {
        if index < storedDescriptors.count {
            var next = map
            next[action] = HotkeysSettingsPresentation.descriptorsAfterRemoving(index: index, from: storedDescriptors)
            autoApply(next)
            return
        }

        let pendingIndex = index - storedDescriptors.count
        var pending = pendingDescriptors
        if pending.indices.contains(pendingIndex) {
            pending.remove(at: pendingIndex)
        }
        pendingTriggerDescriptors[action] = pending.isEmpty ? nil : pending
    }

    private func issueMessage(for action: HotkeyAction, index: Int) -> String? {
        let descriptors = storedDescriptors(for: action)
        guard descriptors.indices.contains(index) else { return nil }
        return HotkeyValidation.issue(
            forAppHotkey: descriptors[index],
            action: action,
            index: index,
            appHotkeys: map,
            voiceShortcut: VoiceActivationSettingsStore.load().shortcut,
            dockShortcuts: HotkeyValidation.liveDockShortcuts()
        )?.message
    }

    private func candidateIssueMessage(_ descriptor: HotkeyDescriptor, for action: HotkeyAction, index: Int) -> String? {
        HotkeyValidation.issue(
            forAppHotkey: descriptor,
            action: action,
            index: index,
            appHotkeys: map,
            voiceShortcut: VoiceActivationSettingsStore.load().shortcut,
            dockShortcuts: HotkeyValidation.liveDockShortcuts()
        )?.message
    }

    private func autoApply(_ updatedMap: [HotkeyAction: [HotkeyDescriptor]]) {
        map = updatedMap
        if let issue = HotkeyValidation.firstIssue(
            in: updatedMap,
            voiceShortcut: VoiceActivationSettingsStore.load().shortcut,
            dockShortcuts: HotkeyValidation.liveDockShortcuts()
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
