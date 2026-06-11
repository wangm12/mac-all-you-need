import AppKit
import Core
import Platform
import SwiftUI

struct DownloadsDestinationView: View {
    let controller: AppController
    @AppStorage("downloadConcurrency", store: AppGroupSettings.defaults) private var concurrency = 3
    @AppStorage("downloadOutputTemplate", store: AppGroupSettings.defaults) private var template = "%(title)s [%(id)s].%(ext)s"
    @AppStorage("downloadDirectory", store: AppGroupSettings.defaults) private var downloadDir = ""
    @AppStorage(DownloadsFunctionTab.storageKey, store: AppGroupSettings.defaults) private var selectedTabRaw = DownloadsFunctionTab.queue.rawValue
    @State private var hotkeyMap = HotkeyMapStore.defaultMap
    @State private var hotkeyRegistrationErrors: [HotkeyAction: String] = [:]
    @State private var showingAddURL = false
    @State private var addURL = ""
    @State private var detectedClipboardURL: String?

    private var selectedTab: Binding<DownloadsFunctionTab> {
        Binding {
            DownloadsFunctionTab.storedSelection(selectedTabRaw)
        } set: { tab in
            selectedTabRaw = tab.rawValue
        }
    }

    var body: some View {
        FunctionPageShell(
            title: "Downloads",
            subtitle: "Queue media downloads, review results, and tune downloader behavior.",
            selection: selectedTab,
            toolbar: {
                MainHeaderShortcutDisplay(
                    text: MainToolHeaderShortcutModel.display(
                        for: .downloads,
                        hotkeys: hotkeyMap,
                        voiceSettings: VoiceActivationSettingsStore.load()
                    ),
                    issueMessage: MainToolHeaderShortcutModel.issue(
                        for: .downloads,
                        hotkeys: hotkeyMap,
                        voiceSettings: VoiceActivationSettingsStore.load()
                    )
                )
            }
        ) {
            switch DownloadsFunctionTab.storedSelection(selectedTabRaw) {
            case .queue:
                FunctionPageScrollContent {
                    clipboardURLDetectedSection
                    downloadsQueueSection
                }
            case .completed:
                FunctionPageScrollContent {
                    downloadsCompletedSection
                }
            case .settings:
                FunctionPageScrollContent {
                    downloadsSettingsSection
                }
            }
        }
        .sheet(isPresented: $showingAddURL) {
            DownloadAddURLSheet(
                urlString: $addURL,
                onCancel: { showingAddURL = false },
                onDownload: submitAddURL
            )
        }
        .background {
            DownloadPickerHost(vm: controller.downloaderVM)
        }
        .onChange(of: concurrency) { _, n in
            Task { await controller.downloader.queue.setMaxConcurrent(n) }
        }
        .onAppear {
            hotkeyMap = HotkeyMapStore.load()
            refreshDetectedClipboardURL()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshDetectedClipboardURL()
        }
        .onReceive(NotificationCenter.default.publisher(for: .pasteboardChanged)) { _ in
            refreshDetectedClipboardURL()
        }
        .onReceive(NotificationCenter.default.publisher(for: .addDownloadRequested)) { _ in
            presentAddURLSheet(prefill: DownloaderViewModel.clipboardVideoURL())
        }
    }

    @ViewBuilder
    private var clipboardURLDetectedSection: some View {
        if let detectedClipboardURL {
            DownloadClipboardURLDetectedBanner(urlString: detectedClipboardURL) {
                enqueueURL(detectedClipboardURL)
            }
        }
    }

    private var downloadsQueueSection: some View {
        MAYNSection(title: "Queue") {
            DownloadsListView(
                vm: controller.downloaderVM,
                filter: .activeQueue,
                onPasteURL: enqueueClipboardURL,
                onAddURL: { presentAddURLSheet(prefill: DownloaderViewModel.clipboardVideoURL()) }
            )
        }
    }

    private var downloadsCompletedSection: some View {
        MAYNSection(title: "Completed") {
            DownloadsListView(
                vm: controller.downloaderVM,
                filter: .completed,
                onPasteURL: enqueueClipboardURL,
                onAddURL: { presentAddURLSheet(prefill: DownloaderViewModel.clipboardVideoURL()) }
            )
        }
    }

    private var downloadsSettingsSection: some View {
        DownloadsSettingsContent(
            concurrency: $concurrency,
            template: $template,
            downloadDir: $downloadDir
        )
    }

    private func presentAddURLSheet(prefill: String?) {
        addURL = prefill ?? ""
        showingAddURL = true
    }

    private func submitAddURL(_ url: String) {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        showingAddURL = false
        addURL = ""
        enqueueURL(trimmed)
    }

    private func enqueueClipboardURL() {
        Task {
            await controller.downloaderVM.enqueueClipboardURL()
            await MainActor.run {
                refreshDetectedClipboardURL()
            }
        }
    }

    private func enqueueURL(_ url: String) {
        Task {
            await controller.downloaderVM.add(url: url)
            await MainActor.run {
                refreshDetectedClipboardURL()
            }
        }
    }

    private func refreshDetectedClipboardURL() {
        detectedClipboardURL = DownloaderViewModel.clipboardVideoURL()
    }

    private func hotkeyBinding(for action: HotkeyAction) -> Binding<Platform.HotkeyDescriptor> {
        Binding(
            get: {
                let defaultDescriptor = action.primaryDefaultDescriptor ?? .defaultClipboard
                let descriptors = hotkeyMap[action] ?? [defaultDescriptor]
                return descriptors.first ?? defaultDescriptor
            },
            set: { descriptor in
                setHotkey(descriptor, for: action)
            }
        )
    }

    private func setHotkey(_ descriptor: Platform.HotkeyDescriptor, for action: HotkeyAction) {
        var descriptors = hotkeyMap[action] ?? action.defaultDescriptors
        if descriptors.isEmpty {
            descriptors = [descriptor]
        } else {
            descriptors[0] = descriptor
        }
        var next = hotkeyMap
        next[action] = descriptors
        autoApplyHotkeys(next, changedAction: action)
    }

    private func hotkeyIssueMessage(for action: HotkeyAction) -> String? {
        let descriptors = hotkeyMap[action] ?? action.defaultDescriptors
        guard let descriptor = descriptors.first ?? action.primaryDefaultDescriptor else {
            return nil
        }
        let validationIssue = HotkeyValidation.issue(
            forAppHotkey: descriptor,
            action: action,
            index: 0,
            appHotkeys: hotkeyMap,
            voiceShortcut: VoiceActivationSettingsStore.load().shortcut,
            dockShortcuts: HotkeyValidation.liveDockShortcuts()
        )?.message
        return HotkeyRecorderControlPresentation.rowIssueMessage(
            validationIssue: validationIssue,
            registrationErrors: hotkeyRegistrationErrors,
            action: action
        )
    }

    private func autoApplyHotkeys(_ next: [HotkeyAction: [Platform.HotkeyDescriptor]], changedAction: HotkeyAction) {
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
                changedAction: changedAction
            )
        }
    }
}

private struct DownloadClipboardURLDetectedBanner: View {
    let urlString: String
    let onEnqueue: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "link")
                .font(.callout.weight(.semibold))
                .foregroundStyle(MAYNTheme.progress)
                .frame(width: MAYNControlMetrics.controlHeight, height: MAYNControlMetrics.controlHeight)
                .background(MAYNTheme.progress.opacity(0.10), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text("Clipboard URL detected")
                    .font(.callout.weight(.semibold))
                Text("\(urlString) is ready to enqueue.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 12)
            MAYNButton("Enqueue", action: onEnqueue)
        }
        .padding(.horizontal, MAYNControlMetrics.rowHorizontalPadding)
        .padding(.vertical, MAYNControlMetrics.rowVerticalPadding)
        .background(MAYNTheme.panel, in: RoundedRectangle(cornerRadius: MAYNControlMetrics.panelRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MAYNControlMetrics.panelRadius, style: .continuous)
                .stroke(MAYNTheme.subtleBorder, lineWidth: 1)
        )
    }
}

private extension Notification.Name {
    static let pasteboardChanged = Notification.Name("NSPasteboardChangedNotification")
}
