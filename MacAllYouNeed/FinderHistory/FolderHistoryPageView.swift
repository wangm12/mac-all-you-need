import Core
import FeatureCore
import Platform
import SwiftUI

/// Configuration page for Finder Folder History (settings tab and main sidebar destination).
struct FolderHistoryPageView: View {
    private let controller: AppController?
    private let embeddedInFinderPreview: Bool
    @State private var hotkeyMap = HotkeyMapStore.defaultMap
    @State private var settings = FolderHistorySettingsStore.load()
    @State private var clearConfirm = false
    @State private var isFeatureEnabled = false
    @State private var statePublisher: FeatureStatePublisher?
    @State private var visitCount = 0

    private var store: FolderHistoryStore? { FolderHistoryStoreLocator.shared() }

    init(controller: AppController? = nil, embeddedInFinderPreview: Bool = false) {
        self.controller = controller
        self.embeddedInFinderPreview = embeddedInFinderPreview
        if let controller {
            _statePublisher = State(initialValue: controller.featureStatePublisher)
        }
    }

    var body: some View {
        Group {
            if embeddedInFinderPreview {
                FunctionPageScrollContent {
                    folderHistorySettingsSections
                }
            } else {
                standalonePage
            }
        }
        .onAppear(perform: onPageAppear)
        .alert("Clear folder history?", isPresented: $clearConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                try? store?.clear()
                refreshVisitCount()
            }
        } message: {
            Text("This removes every folder from your visit history. This cannot be undone.")
        }
    }

    private var standalonePage: some View {
        MAYNSettingsPage(
            title: "Finder Folder History",
            subtitle: "Keeps track of folders you open in Finder. Use the hotkey to browse and reopen them."
        ) {
            if controller != nil {
                featureEnableSection
            }
            folderHistorySettingsSections
        }
        .onAppear(perform: onPageAppear)
        .onReceive(NotificationCenter.default.publisher(for: .featureRuntimeStateChanged)) { _ in
            refreshFeatureEnabled()
        }
    }

    @ViewBuilder
    private var folderHistorySettingsSections: some View {
            MAYNSection(title: "Shortcut") {
                MAYNSettingsRow(
                    title: "History switcher",
                    subtitle: "Opens a searchable list of visited folders."
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
            }

            MAYNSection(title: "Excluded folders") {
                FolderHistoryPathExclusionEditor(paths: excludedPathsBinding) { paths in
                    settings.excludedPaths = paths
                    FolderHistorySettingsStore.save(settings)
                }
            }

            MAYNSection(title: "History") {
                MAYNSettingsRow(
                    title: "Recorded folders",
                    subtitle: visitCount == 0
                        ? "No folders recorded yet."
                        : "\(visitCount) folder\(visitCount == 1 ? "" : "s") in history."
                ) {
                    EmptyView()
                }
                MAYNDivider()
                MAYNSettingsRow(
                    title: "Clear history",
                    subtitle: "Remove all recorded folder visits."
                ) {
                    MAYNButton("Clear…", role: .destructive) {
                        clearConfirm = true
                    }
                }
            }
    }

    private func onPageAppear() {
        hotkeyMap = HotkeyMapStore.load()
        settings = FolderHistorySettingsStore.load()
        refreshFeatureEnabled()
        refreshVisitCount()
    }

    @ViewBuilder
    private var featureEnableSection: some View {
        MAYNSection(title: "Feature") {
            MAYNSettingsRow(
                title: "Finder Folder History",
                subtitle: isFeatureEnabled
                    ? "Recording and the ⌘⇧H switcher are active."
                    : "Off by default. Turn on to record folders and use the switcher."
            ) {
                Toggle("", isOn: $isFeatureEnabled)
                    .labelsHidden()
                    .onChange(of: isFeatureEnabled) { _, enabled in
                        guard let controller else { return }
                        Task {
                            let transition: FeatureManager.Transition = enabled ? .enable : .disable
                            try? await controller.runtime.applyTransition(transition, for: .folderHistory)
                            await statePublisher?.refresh()
                        }
                    }
            }
        }
    }

    private func refreshFeatureEnabled() {
        guard let statePublisher else { return }
        isFeatureEnabled = statePublisher.state(for: .folderHistory).activationState == .enabled
    }

    private func refreshVisitCount() {
        visitCount = (try? store?.list(limit: 10_000).count) ?? 0
    }

    private var excludedPathsBinding: Binding<[String]> {
        Binding(
            get: { settings.excludedPaths },
            set: { settings.excludedPaths = $0 }
        )
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
            index:  0,
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
