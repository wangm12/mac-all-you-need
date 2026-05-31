import AppKit
import Core
import FeatureCore
import Platform
import SwiftUI

struct FinderFolderHistoryPage: View {
    let controller: AppController

    @State private var rows: [FolderHistoryRow] = []
    @State private var searchText = ""
    @State private var featureEnabled = false
    @State private var axGranted = AXIsProcessTrusted()
    @State private var hotkeyMap = HotkeyMapStore.defaultMap
    @State private var hotkeyRegistrationErrors: [HotkeyAction: String] = [:]

    private var store: FolderHistoryStore? { FolderHistoryStoreLocator.shared() }
    private var statePublisher: FeatureStatePublisher { controller.featureStatePublisher }

    private var filtered: [FolderHistoryRow] {
        guard !searchText.isEmpty else { return rows }
        return rows.filter {
            $0.path.localizedCaseInsensitiveContains(searchText)
                || $0.displayName.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        MAYNSettingsPage(
            title: "Finder History",
            subtitle: "Jump back to recently visited Finder folders."
        ) {
            // Status warnings
            if !featureEnabled {
                MAYNSection(title: "Feature Disabled") {
                    MAYNSettingsRow(
                        title: "Enable Finder History",
                        subtitle: "Finder History is currently disabled. Enable it from the Dashboard to start recording."
                    ) {
                        MAYNButton("Go to Dashboard", role: .primary) {
                            // Switch to dashboard
                            AppGroupSettings.defaults.set(
                                MainAppDestination.dashboard.rawValue,
                                forKey: MainAppDestination.storageKey
                            )
                        }
                    }
                }
            } else if !axGranted {
                MAYNSection(title: "Permission Required") {
                    MAYNSettingsRow(
                        title: "Accessibility access needed",
                        subtitle: "Folder recording requires Accessibility permission to read Finder's current folder."
                    ) {
                        MAYNButton("Open Settings", role: .primary) {
                            NSWorkspace.shared.open(
                                URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                            )
                        }
                    }
                }
            }

            // History list
            MAYNSection(title: "Recent Folders (\(rows.count))") {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search folders…", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.callout)
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                    MAYNButton("Refresh", role: .secondary) { reload() }
                }
                .padding(.vertical, 6)

                MAYNDivider()

                if filtered.isEmpty {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "folder.badge.questionmark")
                                .font(.system(size: 28))
                                .foregroundStyle(.secondary)
                            Text(rows.isEmpty
                                 ? "No folders recorded yet.\nOpen Finder, navigate to folders, and make Finder the active app for 2+ seconds each."
                                 : "No matches for \"\(searchText)\"")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.vertical, 24)
                        Spacer()
                    }
                } else {
                    ForEach(Array(filtered.prefix(100).enumerated()), id: \.element.id) { index, row in
                        if index > 0 { MAYNDivider() }
                        HStack(spacing: 10) {
                            FolderHistoryRowIcon(path: row.path, isPinned: row.isPinned)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(row.displayName)
                                    .font(.callout)
                                    .fontWeight(.medium)
                                    .lineLimit(1)
                                Text(row.path)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.head)
                            }
                            Spacer(minLength: 4)
                            Text(relativeDate(row.visitedAt))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            MAYNButton("Open", role: .secondary) {
                                FolderHistoryActions.open(path: row.path)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            // How it works
            MAYNSection(title: "How it works") {
                MAYNSettingsRow(
                    title: "Quick switcher shortcut",
                    subtitle: "Press anywhere to open a searchable history panel."
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
                    title: "Recording",
                    subtitle: "Folders are captured every 1.5 seconds while Finder is the frontmost app. Navigate to a folder and pause for 2 seconds."
                ) {
                    EmptyView()
                }
                MAYNDivider()
                MAYNSettingsRow(
                    title: "Privacy",
                    subtitle: "Only folder paths are stored — folder contents are never read."
                ) {
                    EmptyView()
                }
            }
        }
        .onAppear {
            hotkeyMap = HotkeyMapStore.load()
        }
        .task {
            reload()
            refreshFeatureState()
            // Auto-refresh every 3 seconds while the page is visible.
            for await _ in AsyncStream<Void> { continuation in
                let timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
                    continuation.yield()
                }
                continuation.onTermination = { _ in timer.invalidate() }
            } {
                reload()
                axGranted = AXIsProcessTrusted()
            }
        }
    }

    private func reload() {
        rows = (try? store?.list(limit: 100)) ?? []
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
        let validationIssue = HotkeyValidation.issue(
            forAppHotkey: descriptor,
            action: .finderHistory,
            index: 0,
            appHotkeys: hotkeyMap,
            voiceShortcut: VoiceActivationSettingsStore.load().shortcut,
            dockShortcuts: HotkeyValidation.liveDockShortcuts()
        )?.message
        return HotkeyRecorderControlPresentation.rowIssueMessage(
            validationIssue: validationIssue,
            registrationErrors: hotkeyRegistrationErrors,
            action: .finderHistory
        )
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
        autoApplyHotkeys(next)
    }

    private func autoApplyHotkeys(_ next: [HotkeyAction: [Platform.HotkeyDescriptor]]) {
        hotkeyMap = next
        if HotkeyValidation.firstIssue(
            in: next,
            voiceShortcut: VoiceActivationSettingsStore.load().shortcut,
            dockShortcuts: HotkeyValidation.liveDockShortcuts()
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
                changedAction: .finderHistory
            )
        }
    }

    private func refreshFeatureState() {
        let state = statePublisher.state(for: .folderHistory)
        featureEnabled = state.activationState == .enabled
    }

    private func relativeDate(_ date: Date) -> String {
        let diff = Date().timeIntervalSince(date)
        switch diff {
        case 0..<60: return "just now"
        case 60..<3600: return "\(Int(diff / 60))m ago"
        case 3600..<86400: return "\(Int(diff / 3600))h ago"
        default: return "\(Int(diff / 86400))d ago"
        }
    }
}

private struct FolderHistoryRowIcon: View {
    let path: String
    let isPinned: Bool

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                .resizable()
                .frame(width: 24, height: 24)
            if isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.orange)
                    .offset(x: 3, y: 3)
            }
        }
        .frame(width: 24, height: 24)
    }
}
