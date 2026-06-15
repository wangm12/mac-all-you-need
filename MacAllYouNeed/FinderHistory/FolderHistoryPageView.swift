import AppKit
import ApplicationServices
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
    @State private var axGranted = AXIsProcessTrusted()
    @State private var clearConfirm = false
    @State private var isFeatureEnabled = false
    @State private var statePublisher: FeatureStatePublisher?
    @State private var visitCount = 0
    @State private var captureStatus: String?

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
            if !axGranted {
                MAYNSection(title: "Permission") {
                    AccessibilityPermissionRow(
                        status: PermissionStatusProvider.requiredPermission(isGranted: axGranted),
                        isHighlighted: false,
                        onAction: requestAccessibility
                    )
                }
            }

            MAYNSection(title: "Status") {
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
                    title: "Capture current Finder folder",
                    subtitle: captureStatus ?? "Use while Finder is frontmost to test recording."
                ) {
                    MAYNButton("Capture now") {
                        captureCurrentFinderFolder()
                    }
                }
            }

            MAYNSection(title: "Recording") {
                MAYNSettingsRow(
                    title: "Pause recording",
                    subtitle: "Temporarily stop adding folders to history."
                ) {
                    Toggle("", isOn: pauseBinding)
                        .labelsHidden()
                }
                MAYNDivider()
                MAYNSettingsRow(
                    title: "How it works",
                    subtitle: "Folders are recorded when you browse in Finder while this feature is enabled."
                ) {
                    EmptyView()
                }
            }

            MAYNSection(title: "Quick switcher") {
                MAYNSettingsRow(
                    title: "Shortcut",
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

            MAYNSection(title: "Dock & Folder Preview") {
                MAYNSettingsRow(
                    title: "Works with Dock folder previews",
                    subtitle: "When Dock previews are enabled, use “Browse in Mac All You Need” or “Add to Folder History” from a dock folder stack."
                ) {
                    EmptyView()
                }
                MAYNDivider()
                MAYNSettingsRow(
                    title: "Folder Preview",
                    subtitle: "Open any history path in the Browse Folder window from the switcher or menu bar."
                ) {
                    EmptyView()
                }
            }

            MAYNSection(title: "Privacy") {
                MAYNSettingsRow(
                    title: "What is stored",
                    subtitle: "Only folder paths are recorded — never the contents of any folder."
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
        axGranted = AXIsProcessTrusted()
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

    private func captureCurrentFinderFolder() {
        guard axGranted else {
            captureStatus = "Grant Accessibility first, then try again."
            return
        }
        guard let pid = NSWorkspace.shared.runningApplications
            .first(where: { $0.bundleIdentifier == "com.apple.finder" })?
            .processIdentifier
        else {
            captureStatus = "Finder is not running."
            return
        }
        guard let path = FolderHistoryFinderPathResolver.resolve(pid: pid, axReader: SystemFolderHistoryAXReader()) else {
            captureStatus = "Could not read the front Finder folder. Allow Automation for Finder if macOS prompts you."
            return
        }
        do {
            _ = try store?.upsert(path: path, now: Date())
            refreshVisitCount()
            captureStatus = "Recorded \(path)"
        } catch {
            captureStatus = "Could not save: \(error.localizedDescription)"
        }
    }

    private func requestAccessibility() {
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private var pauseBinding: Binding<Bool> {
        Binding(
            get: { settings.isPaused },
            set: { newValue in
                settings.isPaused = newValue
                FolderHistorySettingsStore.save(settings)
            }
        )
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
