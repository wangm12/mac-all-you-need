import AppKit
import Core
import CoreFoundation
import FeatureCore
import ApplicationServices
import Platform
import SwiftUI

struct ClipboardDestinationView: View {
    let controller: AppController
    @AppStorage("retention.maxAgeDays", store: AppGroupSettings.defaults) private var maxAgeDays = 30
    @AppStorage("autoPaste.behavior", store: AppGroupSettings.defaults) private var pasteBehavior = "pasteIntoFocused"
    @AppStorage("autoPaste.delayMs", store: AppGroupSettings.defaults) private var pasteDelay = 150
    @AppStorage(ClipboardFunctionTab.storageKey, store: AppGroupSettings.defaults) private var selectedTabRaw = ClipboardFunctionTab.history.rawValue
    @AppStorage(SnippetExpansionSettings.modeKey, store: AppGroupSettings.defaults) private var expansionModeRaw = SnippetExpansionSettings.defaultMode.rawValue
    @State private var blockedApps: [String] = ExcludedAppsStore.load()
    @State private var hotkeyMap: [HotkeyAction: [Platform.HotkeyDescriptor]] = HotkeyMapStore.defaultMap
    @State private var hotkeyRegistrationErrors: [HotkeyAction: String] = [:]
    @State private var historyItems: [ClipboardItemMeta] = []
    @State private var historySearch = ""
    @State private var historyPage = 0
    @State private var historyTypeFilter: ClipboardHistoryTypeFilter = .all
    @State private var historySortMode: ClipboardHistorySortMode = .recent
    @State private var isHistoryLoading = false
    @State private var historyLoadTask: Task<Void, Never>?
    @State private var storeChangeSyncTask: Task<Void, Never>?
    /// Cached once per history refresh — never hit the pinboard DB from SwiftUI body.
    @State private var pinnedHistoryItemIDs: Set<String> = []
    /// Bundle ID of the app that was frontmost when the main window was last
    /// opened. Used for context-aware ranking of clipboard history items.
    @State private var contextBundleID: String?
    private static let historyPageSize = 20

    private var selectedTab: Binding<ClipboardFunctionTab> {
        Binding {
            ClipboardFunctionTab.storedSelection(selectedTabRaw)
        } set: { tab in
            selectedTabRaw = tab.rawValue
        }
    }

    private var expansionMode: SnippetExpansionMode {
        SnippetExpansionMode(rawValue: expansionModeRaw) ?? SnippetExpansionSettings.defaultMode
    }

    private var activeClipboardTab: ClipboardFunctionTab {
        ClipboardFunctionTab.storedSelection(selectedTabRaw)
    }

    var body: some View {
        FunctionPageShell(
            title: "Clipboard",
            subtitle: "History, snippets, and paste behavior for local clipboard memory.",
            selection: selectedTab,
            tabStripMaxWidth: 560,
            toolbar: {
                Button {
                    controller.clipboardDock.show()
                } label: {
                    HStack(spacing: 6) {
                        Text("Open Dock")
                            .font(.system(size: 12, weight: .semibold))
                        MAYNHotkeyDisplay(
                            text: MainToolHeaderShortcutModel.display(
                                for: .clipboard,
                                hotkeys: hotkeyMap,
                                voiceSettings: VoiceActivationSettingsStore.load()
                            ) ?? "⇧⌘V"
                        )
                    }
                }
                .buttonStyle(.plain)
                .help("Open clipboard dock")
            }
        ) {
            switch ClipboardFunctionTab.storedSelection(selectedTabRaw) {
            case .history:
                FunctionPageScrollContent {
                    clipboardHistorySection
                }
            case .snippets:
                SnippetsListView(model: controller.clipboardDeps.dockModel)
            case .settings:
                FunctionPageScrollContent {
                    clipboardSettingsSection
                }
            }
        }
        .onAppear {
            contextBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            hotkeyMap = HotkeyMapStore.load()
            blockedApps = ExcludedAppsStore.load()
            seedHistoryPreviewFromReader()
            if ClipboardHistoryLoadPolicy.shouldLoadFullHistory(for: activeClipboardTab) {
                scheduleClipboardHistoryReload()
            }
        }
        .onDisappear {
            historyLoadTask?.cancel()
            historyLoadTask = nil
            storeChangeSyncTask?.cancel()
            storeChangeSyncTask = nil
            isHistoryLoading = false
        }
        .onReceive(NotificationCenter.default.publisher(for: .clipboardStoreDidChange)) { _ in
            scheduleStoreChangeHistorySync()
        }
        .onChange(of: selectedTabRaw) { _, _ in
            if ClipboardHistoryLoadPolicy.shouldLoadFullHistory(for: activeClipboardTab) {
                seedHistoryPreviewFromReader()
                scheduleClipboardHistoryReload()
            } else {
                cancelClipboardHistoryLoad()
            }
        }
        .onChange(of: historySearch) { _, _ in
            historyPage = 0
            guard ClipboardHistoryLoadPolicy.shouldLoadFullHistory(for: activeClipboardTab) else { return }
            scheduleClipboardHistoryReload(debounceMilliseconds: 300)
        }
        .onChange(of: historyTypeFilter) { _, _ in
            historyPage = 0
        }
        .onChange(of: historySortMode) { _, _ in
            historyPage = 0
        }
        .onChange(of: historyItems.map(\.id.rawValue)) { _, _ in
            clampClipboardHistoryPage()
        }
        .onChange(of: maxAgeDays) { _, _ in
            postRetentionSettingsChangedDarwin()
            guard ClipboardHistoryLoadPolicy.shouldLoadFullHistory(for: activeClipboardTab) else { return }
            scheduleClipboardHistoryReload()
        }
    }

    private var clipboardHistorySection: some View {
        Group {
            MAYNSection(
                title: "All items",
                subtitle: "Search and page through the full local clipboard history.",
                surfaceStyle: .listPanel
            ) {
                let state = clipboardHistoryState
                ClipboardHistorySearchBar(
                    query: $historySearch,
                    resultText: state.totalItems == 1 ? "1 item" : "\(state.totalItems) items"
                )

                ClipboardHistoryFilterChips(
                    typeFilter: $historyTypeFilter,
                    sortMode: $historySortMode
                )

                MAYNDivider()

                if isHistoryLoading, historyItems.isEmpty {
                    MAYNSettingsRow(title: "Loading history", subtitle: "Reading local clipboard metadata.") {
                        ProgressView()
                            .controlSize(.small)
                    }
                } else if historyItems.isEmpty {
                    MAYNSettingsRow(title: "No items yet", subtitle: "Copy text, images, links, or files to start history capture.") {
                        EmptyView()
                    }
                } else if state.totalItems == 0 {
                    MAYNSettingsRow(title: "No matching items", subtitle: "Clear the search field or try a different term.") {
                        EmptyView()
                    }
                } else {
                    let sections = clipboardHistorySections(from: state.visibleItems)
                    ForEach(sections) { section in
                        if !section.title.isEmpty {
                            Text(section.title)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 16)
                                .padding(.top, section.id == sections.first?.id ? 4 : 12)
                                .padding(.bottom, 4)
                        }
                        ForEach(Array(section.items.enumerated()), id: \.element.id.rawValue) { index, item in
                            if index > 0 || !section.title.isEmpty { MAYNDivider() }
                            let flatIndex = flatClipboardHistoryIndex(for: item, in: state.visibleItems)
                            MainClipboardRecentRow(
                                item: item,
                                imageLoader: controller.clipboardDeps.imageLoader,
                                appIcons: controller.clipboardDeps.appIcons,
                                isSelected: controller.clipboardReader.selectedIDs.contains(item.id.rawValue),
                                quickShortcut: flatIndex.flatMap { $0 < 9 ? "⌘\($0 + 1)" : nil },
                                onSelect: {
                                    selectClipboardHistoryItem(item)
                                },
                                onCopy: {
                                    copyClipboardHistoryItems(ids: [item.id.rawValue])
                                },
                                onPin: {
                                    pinClipboardHistoryItem(item)
                                },
                                onDelete: {
                                    deleteClipboardHistoryItem(item)
                                },
                                onReveal: clipboardRevealAction(for: item)
                            )
                        }
                    }

                    MAYNDivider()
                    MAYNListPaginationFooter(
                        state: state.pagination,
                        visibleItemCount: state.visibleItems.count,
                        goToPage: { historyPage = $0 }
                    )
                }
            }
            .focusable()
            .focusEffectDisabled()
            .onKeyPress { keyPress in
                handleClipboardHistoryKeyPress(keyPress)
            }
        }
    }

    private var clipboardHistoryState: MainClipboardHistoryPageState {
        let ranked = historySearch.isEmpty
            ? ContextAwareRanker.rank(historyItems, forBundleID: contextBundleID)
            : historyItems
        let filtered = ClipboardHistoryPresentation.filtered(
            ranked,
            typeFilter: historyTypeFilter
        )
        let sorted = ClipboardHistoryPresentation.sorted(
            filtered,
            mode: historySortMode,
            contextBundleID: contextBundleID
        )
        return MainClipboardHistoryPresentation.state(
            items: sorted,
            query: "",
            requestedPage: historyPage,
            pageSize: Self.historyPageSize
        )
    }

    private func clipboardHistorySections(from items: [ClipboardItemMeta]) -> [ClipboardHistorySectionModel] {
        ClipboardHistoryPresentation.sections(
            items: items,
            isPinned: { pinnedHistoryItemIDs.contains($0.id.rawValue) }
        )
    }

    private func refreshPinnedHistoryItemIDs() {
        guard let pinned = try? PinnedPinboard.findOrCreate(in: controller.clipboardDeps.pinboardStore) else {
            pinnedHistoryItemIDs = []
            return
        }
        pinnedHistoryItemIDs = Set(pinned.itemIDs.map(\.rawValue))
    }

    private func flatClipboardHistoryIndex(for item: ClipboardItemMeta, in items: [ClipboardItemMeta]) -> Int? {
        items.firstIndex(where: { $0.id == item.id })
    }

    private func clipboardRevealAction(for item: ClipboardItemMeta) -> (() -> Void)? {
        guard ClipboardHistoryPresentation.isFileItem(item) else { return nil }
        return {
            Task {
                guard let urls = await controller.clipboardDeps.fileLoader.urls(recordID: item.id.rawValue),
                      let url = urls.first
                else { return }
                await MainActor.run {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
        }
    }

    private var filteredClipboardHistoryItems: [ClipboardItemMeta] {
        clipboardHistoryState.filteredItems
    }

    private var visibleClipboardHistoryItems: [ClipboardItemMeta] {
        clipboardHistoryState.visibleItems
    }

    private var clipboardSettingsSection: some View {
        Group {
            MAYNSection(title: "Quick Start", contentLayout: .prose) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Keep the recommended shortcut, choose how pasting should behave, and leave Smart Text on unless you need a simpler clipboard.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("The rest of these options are for exclusions, history retention, and power-user tweaks.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            MAYNSection(title: "Shortcut") {
                MAYNSettingsRow(
                    title: "Clipboard shortcut",
                    subtitle: "Global trigger for opening the clipboard dock."
                ) {
                    HotkeyRecorderControl(
                        descriptor: hotkeyBinding(for: .clipboard),
                        issueMessage: hotkeyIssueMessage(for: .clipboard),
                        candidateIssueMessage: { hotkeyCandidateIssueMessage($0, for: .clipboard) },
                        defaultDescriptor: HotkeyAction.clipboard.primaryDefaultDescriptor,
                        recorderWidth: 112,
                        errorWidth: 260,
                        reset: {
                            if let descriptor = HotkeyAction.clipboard.primaryDefaultDescriptor {
                                setHotkey(descriptor, for: .clipboard)
                            }
                        }
                    )
                }
            }

            MAYNSection(title: "Capture") {
                MAYNSettingsRow(
                    title: "History window",
                    subtitle: "Only list and search items newer than this. Matches Storage → History size → Maximum age; nightly cleanup uses the same clock."
                ) {
                    MAYNDropdown(
                        selection: $maxAgeDays,
                        options: [0, 7, 30, 90, 365],
                        title: clipboardHistoryMaxAgeTitle,
                        width: MAYNControlMetrics.widePickerWidth
                    )
                }
            }

            MAYNSection(
                title: "Ignored apps",
                subtitle: "Clipboard content copied from these apps will never be saved to history."
            ) {
                BundleIDExclusionEditor(bundleIDs: $blockedApps) { ExcludedAppsStore.save($0) }
            }

            MAYNSection(title: "Paste behavior") {
                MAYNSettingsRow(
                    title: "When picking an item",
                    subtitle: "Choose whether the clipboard dock inserts into the focused app or only copies."
                ) {
                    MAYNDropdown(
                        selection: $pasteBehavior,
                        options: pasteBehaviorOptions,
                        title: pasteBehaviorTitle,
                        width: MAYNControlMetrics.widePickerWidth
                    )
                }

                if pasteBehavior == "copyThenPaste" {
                    MAYNDivider()
                    MAYNSettingsRow(
                        title: "Paste delay",
                        subtitle: "Wait after copying before sending Command-V."
                    ) {
                        MAYNNumericStepper(
                        text: "\(pasteDelay) ms",
                        value: $pasteDelay,
                        range: 50...2000,
                        step: 50,
                        presets: [50, 100, 150, 250, 500, 1000, 2000],
                        suffix: "ms"
                    )
                }
                }
            }

            ClipboardDockHeightSection(controller: controller)

            SearchPreferencesSection()

            MAYNSection(title: "Snippets") {
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
            }

            SmartTextEnableSection(controller: controller)
        }
    }

    private let pasteBehaviorOptions = ["pasteIntoFocused", "copyOnly", "copyThenPaste"]

    private func clipboardHistoryMaxAgeTitle(_ days: Int) -> String {
        switch days {
        case 0:
            "Forever"
        case 1:
            "1 day"
        default:
            "\(days) days"
        }
    }

    private func postRetentionSettingsChangedDarwin() {
        let name = "com.macallyouneed.settings-changed" as CFString
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(name),
            nil,
            nil,
            true
        )
    }

    private func pasteBehaviorTitle(_ behavior: String) -> String {
        switch behavior {
        case "pasteIntoFocused":
            "Paste into focused app"
        case "copyOnly":
            "Just copy"
        case "copyThenPaste":
            "Copy, then paste"
        default:
            behavior
        }
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

    private func hotkeyCandidateIssueMessage(_ descriptor: Platform.HotkeyDescriptor, for action: HotkeyAction) -> String? {
        HotkeyValidation.issue(
            forAppHotkey: descriptor,
            action: action,
            index: 0,
            appHotkeys: hotkeyMap,
            voiceShortcut: VoiceActivationSettingsStore.load().shortcut,
            dockShortcuts: HotkeyValidation.liveDockShortcuts()
        )?.message
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

    /// Show dock/reader items immediately so History never sits on an empty spinner.
    private func seedHistoryPreviewFromReader() {
        guard historyItems.isEmpty else { return }
        let preview = controller.clipboardReader.items
        guard !preview.isEmpty else { return }
        let limit = ClipboardHistoryWindow.listParameters().fetchLimit
        historyItems = LocalClipboardReader.deduplicate(preview, limit: limit)
    }

    private func scheduleClipboardHistoryReload(debounceMilliseconds: UInt64 = 0) {
        guard ClipboardHistoryLoadPolicy.shouldLoadFullHistory(for: activeClipboardTab) else { return }
        historyLoadTask?.cancel()
        historyLoadTask = Task { @MainActor in
            if debounceMilliseconds > 0 {
                try? await Task.sleep(for: .milliseconds(debounceMilliseconds))
            }
            guard !Task.isCancelled else { return }
            await loadClipboardHistory()
        }
    }

    private func cancelClipboardHistoryLoad() {
        historyLoadTask?.cancel()
        historyLoadTask = nil
        isHistoryLoading = false
    }

    private func scheduleStoreChangeHistorySync() {
        guard ClipboardHistoryLoadPolicy.shouldLoadFullHistory(for: activeClipboardTab) else { return }
        storeChangeSyncTask?.cancel()
        storeChangeSyncTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            // Avoid restarting the initial load while the spinner is still up.
            guard !(isHistoryLoading && historyItems.isEmpty) else { return }
            scheduleClipboardHistoryReload()
        }
    }

    @MainActor
    private func loadClipboardHistory() async {
        guard ClipboardHistoryLoadPolicy.shouldLoadFullHistory(for: activeClipboardTab) else { return }

        seedHistoryPreviewFromReader()

        guard controller.clipboardReader.store != nil else {
            if historyItems.isEmpty {
                historyItems = controller.clipboardReader.items
            }
            isHistoryLoading = false
            return
        }

        let showSpinner = historyItems.isEmpty
        if showSpinner {
            isHistoryLoading = true
        }
        defer { isHistoryLoading = false }

        guard !Task.isCancelled else { return }

        let params = ClipboardHistoryWindow.listParameters()
        let limit = params.fetchLimit
        let trimmedSearch = historySearch.trimmingCharacters(in: .whitespacesAndNewlines)
        let fuzzyEnabled = AppGroupSettings.defaults.object(forKey: "search.fuzzy") as? Bool ?? false

        // Coalesce with other clipboard reads on `ClipboardWorker` instead of opening a
        // second concurrent GRDB reader that can wedge the shared database queue.
        let loaded = await controller.clipboardDeps.clipboardWorker.loadHistoryMetas(
            query: trimmedSearch.isEmpty ? nil : trimmedSearch,
            limit: limit,
            fuzzyEnabled: fuzzyEnabled
        )

        guard !Task.isCancelled else { return }

        refreshPinnedHistoryItemIDs()

        let fetched = trimmedSearch.isEmpty
            ? LocalClipboardReader.deduplicate(loaded, limit: limit)
            : loaded

        historyItems = fetched
        clampClipboardHistoryPage()
    }

    private func reloadClipboardHistory() {
        scheduleClipboardHistoryReload()
    }

    private func clampClipboardHistoryPage() {
        let state = clipboardHistoryState
        historyPage = state.currentPage
    }

    private func selectClipboardHistoryItem(_ item: ClipboardItemMeta) {
        let reader = controller.clipboardReader
        let id = item.id.rawValue
        let modifiers = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let items = filteredClipboardHistoryItems

        if modifiers.contains(.command) {
            if reader.selectedIDs.contains(id) {
                reader.selectedIDs.remove(id)
            } else {
                reader.selectedIDs.insert(id)
            }
            reader.anchorID = id
            return
        }

        if modifiers.contains(.shift),
           let anchorID = reader.anchorID,
           let anchorIndex = items.firstIndex(where: { $0.id.rawValue == anchorID }),
           let targetIndex = items.firstIndex(where: { $0.id == item.id })
        {
            let lower = min(anchorIndex, targetIndex)
            let upper = max(anchorIndex, targetIndex)
            for row in items[lower...upper] {
                reader.selectedIDs.insert(row.id.rawValue)
            }
            return
        }

        reader.selectedIDs = [id]
        reader.anchorID = id
    }

    private func handleClipboardHistoryKeyPress(_ keyPress: KeyPress) -> KeyPress.Result {
        let raw = keyPress.key.character
        let reader = controller.clipboardReader

        if keyPress.modifiers.contains(.command), String(raw).lowercased() == "a" {
            reader.selectedIDs = Set(filteredClipboardHistoryItems.map { $0.id.rawValue })
            reader.anchorID = filteredClipboardHistoryItems.first?.id.rawValue
            return .handled
        }

        if keyPress.modifiers.contains(.command), String(raw).lowercased() == "c" {
            copyClipboardHistoryItems(ids: effectiveClipboardHistoryIDs())
            return .handled
        }

        if keyPress.modifiers.contains(.command), let digit = Int(String(raw)), (1 ... 9).contains(digit) {
            let items = visibleClipboardHistoryItems
            guard items.indices.contains(digit - 1) else { return .ignored }
            copyClipboardHistoryItems(ids: [items[digit - 1].id.rawValue])
            return .handled
        }

        switch raw {
        case " ":
            if ClipboardSystemQuickLookCoordinator.shared.isVisible {
                ClipboardSystemQuickLookCoordinator.shared.dismiss()
            } else {
                previewClipboardHistoryItem(id: effectiveClipboardHistoryIDs().first)
            }
            return .handled
        case Character(UnicodeScalar(NSDownArrowFunctionKey)!):
            moveClipboardHistorySelection(delta: 1)
            return .handled
        case Character(UnicodeScalar(NSUpArrowFunctionKey)!):
            moveClipboardHistorySelection(delta: -1)
            return .handled
        default:
            return .ignored
        }
    }

    private func moveClipboardHistorySelection(delta: Int) {
        let reader = controller.clipboardReader
        let items = visibleClipboardHistoryItems
        guard !items.isEmpty else { return }
        let currentIndex = reader.anchorID.flatMap { id in
            items.firstIndex { $0.id.rawValue == id }
        } ?? 0
        let nextIndex = min(max(currentIndex + delta, 0), items.count - 1)
        let nextID = items[nextIndex].id.rawValue
        reader.selectedIDs = [nextID]
        reader.anchorID = nextID
        if ClipboardSystemQuickLookCoordinator.shared.isVisible {
            previewClipboardHistoryItem(id: nextID)
        }
    }

    private func effectiveClipboardHistoryIDs() -> [String] {
        let reader = controller.clipboardReader
        let items = filteredClipboardHistoryItems
        if !reader.selectedIDs.isEmpty {
            return items.map(\.id.rawValue).filter { reader.selectedIDs.contains($0) }
        }
        if let anchorID = reader.anchorID {
            return [anchorID]
        }
        return items.first.map { [$0.id.rawValue] } ?? []
    }

    private func pinClipboardHistoryItem(_ item: ClipboardItemMeta) {
        Task {
            await controller.clipboardDeps.dockModel.togglePin(itemID: item.id.rawValue)
            refreshPinnedHistoryItemIDs()
        }
    }

    private func deleteClipboardHistoryItem(_ item: ClipboardItemMeta) {
        let id = item.id.rawValue
        Task {
            await controller.clipboardDeps.dockModel.deleteItems(itemIDs: [id])
            await MainActor.run {
                controller.clipboardReader.selectedIDs.remove(id)
                if controller.clipboardReader.anchorID == id {
                    controller.clipboardReader.anchorID = nil
                }
            }
        }
    }

    private func copyClipboardHistoryItems(ids: [String]) {
        guard let store = controller.clipboardReader.store,
              !ids.isEmpty
        else { return }

        if ids.count == 1,
           let id = ids.first,
           let recordID = RecordID(rawValue: id),
           let body = try? store.body(for: recordID)
        {
            ClipboardXPCService.restoreToPasteboard(
                body: body,
                blobs: controller.clipboardDeps.blobs,
                pasteboard: .general
            )
            NSPasteboard.general.setData(Data([0]), forType: PasteboardUTI.daemonWrite)
            CopyHUD.show("Copied")
            return
        }

        let strings = ids.compactMap { id -> String? in
            guard let recordID = RecordID(rawValue: id),
                  let body = try? store.body(for: recordID)
            else { return nil }
            return plainClipboardHistoryText(from: body)
        }
        guard !strings.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(strings.joined(separator: "\n"), forType: .string)
        NSPasteboard.general.setData(Data([0]), forType: PasteboardUTI.daemonWrite)
        CopyHUD.show(strings.count == 1 ? "Copied" : "Copied \(strings.count)")
    }

    private func previewClipboardHistoryItem(id: String?) {
        guard let id,
              let recordID = RecordID(rawValue: id),
              let store = controller.clipboardReader.store,
              let body = try? store.body(for: recordID)
        else { return }

        let itemTitle = visibleClipboardHistoryItems
            .first { $0.id.rawValue == id }
            .map { $0.customLabel ?? $0.preview }?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let title = itemTitle.flatMap { $0.isEmpty ? nil : $0 } ?? "Clipboard Preview"
        ClipboardSystemQuickLookCoordinator.shared.show(
            record: body,
            title: title,
            blobs: controller.clipboardDeps.blobs
        )
    }

    private func plainClipboardHistoryText(from body: ClipboardRecord) -> String? {
        switch body {
        case let .text(text):
            return text
        case let .html(html):
            return plainHTMLString(html)
        case let .rtf(data):
            return NSAttributedString(rtf: data, documentAttributes: nil)?.string
        case let .files(urls):
            return urls.map(\.path).joined(separator: "\n")
        case .image:
            return nil
        }
    }

    private func plainHTMLString(_ html: String) -> String {
        if let data = html.data(using: .utf8),
           let attributed = NSAttributedString(html: data, documentAttributes: nil) {
            return attributed.string.trimmingCharacters(in: .newlines)
        }
        return html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }
}

private enum ClipboardHistoryTypeFilter: String, CaseIterable, Identifiable {
    case all
    case text
    case link
    case file
    case image

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .text: "Text"
        case .link: "Link"
        case .file: "File"
        case .image: "Image"
        }
    }
}

private enum ClipboardHistorySortMode: String, CaseIterable, Identifiable {
    case recent
    case oldest
    case app

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recent: "Recent"
        case .oldest: "Oldest"
        case .app: "App"
        }
    }
}

private enum ClipboardHistoryPresentation {
    static func isFileItem(_ item: ClipboardItemMeta) -> Bool {
        if case .symbol("doc") = MainClipboardItemPresentation.previewKind(for: item) {
            return true
        }
        return item.preview.hasPrefix("(") && item.preview.localizedCaseInsensitiveContains("file")
    }

    static func filtered(
        _ items: [ClipboardItemMeta],
        typeFilter: ClipboardHistoryTypeFilter
    ) -> [ClipboardItemMeta] {
        guard typeFilter != .all else { return items }
        return items.filter { matchesType($0, filter: typeFilter) }
    }

    static func sorted(
        _ items: [ClipboardItemMeta],
        mode: ClipboardHistorySortMode,
        contextBundleID: String?
    ) -> [ClipboardItemMeta] {
        switch mode {
        case .recent:
            return items.sorted { $0.modified > $1.modified }
        case .oldest:
            return items.sorted { $0.modified < $1.modified }
        case .app:
            return ContextAwareRanker.rank(items, forBundleID: contextBundleID)
        }
    }

    static func sections(
        items: [ClipboardItemMeta],
        isPinned: (ClipboardItemMeta) -> Bool
    ) -> [ClipboardHistorySectionModel] {
        let pinned = items.filter(isPinned)
        let unpinned = items.filter { !isPinned($0) }
        let today = unpinned.filter { Calendar.current.isDateInToday($0.modified) }
        let older = unpinned.filter { !Calendar.current.isDateInToday($0.modified) }

        var result: [ClipboardHistorySectionModel] = []
        if !pinned.isEmpty {
            result.append(.init(id: "pinned", title: "Pinned", items: pinned))
        }
        if !today.isEmpty {
            result.append(.init(id: "today", title: "Today", items: today))
        }
        if !older.isEmpty {
            let title = pinned.isEmpty && today.isEmpty ? "" : "Earlier"
            result.append(.init(id: "earlier", title: title, items: older))
        }
        if result.isEmpty, !items.isEmpty {
            result.append(.init(id: "all", title: "", items: items))
        }
        return result
    }

    private static func matchesType(_ item: ClipboardItemMeta, filter: ClipboardHistoryTypeFilter) -> Bool {
        switch filter {
        case .all:
            return true
        case .text:
            if case .symbol("doc.plaintext") = MainClipboardItemPresentation.previewKind(for: item) { return true }
            return !isFileItem(item) && !item.preview.hasPrefix("http")
                && MainClipboardItemPresentation.previewKind(for: item) != .imageThumbnail(recordID: item.id.rawValue)
        case .link:
            return item.preview.hasPrefix("http")
        case .file:
            return isFileItem(item)
        case .image:
            if case .imageThumbnail = MainClipboardItemPresentation.previewKind(for: item) { return true }
            return false
        }
    }
}

private struct ClipboardHistorySectionModel: Identifiable {
    let id: String
    let title: String
    let items: [ClipboardItemMeta]
}

private struct ClipboardHistoryFilterChips: View {
    @Binding var typeFilter: ClipboardHistoryTypeFilter
    @Binding var sortMode: ClipboardHistorySortMode
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Text("Type:")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(ClipboardHistoryTypeFilter.allCases) { option in
                    ClipboardHistoryFilterChip(
                        title: option.title,
                        isSelected: typeFilter == option
                    ) {
                        typeFilter = option
                    }
                }
            }
            HStack(spacing: 6) {
                Text("Sort:")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(ClipboardHistorySortMode.allCases) { option in
                    ClipboardHistoryFilterChip(
                        title: option.title,
                        isSelected: sortMode == option
                    ) {
                        sortMode = option
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .animation(MAYNMotion.controlAnimation(reduceMotion: reduceMotion), value: typeFilter)
        .animation(MAYNMotion.controlAnimation(reduceMotion: reduceMotion), value: sortMode)
    }
}

private struct ClipboardHistoryFilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(MAYNSelectionLabelStyle.weight(isSelected: isSelected)))
                .foregroundStyle(MAYNSelectionLabelStyle.foreground(isSelected: isSelected))
                .padding(.horizontal, 10)
                .frame(height: 28)
                .maynSelectionBackground(isSelected: isSelected, isHovering: isHovering, shape: .capsule)
                .overlay(Capsule().stroke(MAYNTheme.subtleBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(MAYNMotion.hoverAnimation(reduceMotion: reduceMotion), value: isHovering)
    }
}

private struct ClipboardHistorySearchBar: View {
    @Binding var query: String
    let resultText: String
    @FocusState private var isFocused: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(MAYNTheme.textTertiary(colorScheme))

            TextField("Search all clipboard items", text: $query)
                .textFieldStyle(.plain)
                .font(.callout)
                .focused($isFocused)

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(MAYNTheme.textSecondary(colorScheme))
                }
                .buttonStyle(.plain)
            }

            Text(resultText)
                .font(.caption)
                .foregroundStyle(MAYNTheme.textTertiary(colorScheme))
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: MAYNControlMetrics.controlRadius, style: .continuous)
                .strokeBorder(
                    isFocused ? MAYNTheme.focusRing : (isHovering ? MAYNTheme.strongBorder : MAYNTheme.hairline),
                    lineWidth: 1
                )
        }
        .onHover { isHovering = $0 }
        .animation(MAYNMotion.hoverAnimation(reduceMotion: reduceMotion), value: isHovering)
        .animation(MAYNMotion.controlAnimation(reduceMotion: reduceMotion), value: isFocused)
    }
}

private struct MainClipboardRecentRow: View {
    let item: ClipboardItemMeta
    let imageLoader: ImageBlobLoader
    let appIcons: AppIconResolver
    let isSelected: Bool
    var quickShortcut: String? = nil
    let onSelect: () -> Void
    let onCopy: () -> Void
    let onPin: () -> Void
    let onDelete: () -> Void
    var onReveal: (() -> Void)? = nil
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    var body: some View {
        switch MainClipboardItemPresentation.previewKind(for: item) {
        case let .imageThumbnail(recordID):
            MainClipboardImageRecentRow(
                item: item,
                recordID: recordID,
                imageLoader: imageLoader,
                appIcons: appIcons,
                isSelected: isSelected,
                isHovering: isHovering,
                onSelect: onSelect,
                onCopy: onCopy,
                onPin: onPin,
                onDelete: onDelete,
                onReveal: onReveal,
                quickShortcut: quickShortcut
            )
            .onHover { isHovering = $0 }
        case let .symbol(symbol):
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.customLabel ?? item.preview)
                        .font(.callout)
                        .lineLimit(2)
                    Text(CompactTimestamp.format(item.modified))
                        .font(.caption)
                        .foregroundStyle(
                            MAYNSelectionLabelStyle.subtitle(
                                isSelected: isSelected,
                                scheme: colorScheme
                            )
                        )
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if isHovering {
                    ClipboardHistoryRowActions(
                        isSelected: isSelected,
                        onCopy: onCopy,
                        onPin: onPin,
                        onDelete: onDelete,
                        onReveal: onReveal,
                        quickShortcut: quickShortcut
                    )
                }

                ClipboardHistoryIconView(
                    item: item,
                    fallbackSymbol: symbol,
                    appIcons: appIcons,
                    size: 28,
                    symbolFontSize: 15,
                    cornerRadius: 7
                )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(minHeight: 56)
            .frame(maxWidth: .infinity, alignment: .leading)
            .maynSelectionBackground(
                isSelected: isSelected,
                isHovering: isHovering,
                shape: .rounded(10)
            )
            .foregroundStyle(MAYNTheme.textPrimary(colorScheme))
            .contentShape(Rectangle())
            .onTapGesture(perform: onSelect)
            .simultaneousGesture(
                TapGesture(count: 2).onEnded {
                    onCopy()
                }
            )
            .animation(MAYNMotion.hoverAnimation(reduceMotion: reduceMotion), value: isHovering)
            .onHover { isHovering = $0 }
        }
    }
}

private struct ClipboardHistoryRowActions: View {
    let isSelected: Bool
    let onCopy: () -> Void
    let onPin: () -> Void
    let onDelete: () -> Void
    var onReveal: (() -> Void)? = nil
    var quickShortcut: String? = nil
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 4) {
            rowActionButton(symbol: "doc.on.doc", label: "Copy", action: onCopy)
            if let onReveal {
                rowActionButton(symbol: "folder", label: "Reveal in Finder", action: onReveal)
            }
            rowActionButton(symbol: "pin", label: "Pin", action: onPin)
            rowActionButton(symbol: "trash", label: "Delete", action: onDelete)
            if let quickShortcut {
                MAYNKeycap(text: quickShortcut)
                    .accessibilityLabel("Shortcut \(quickShortcut)")
            }
        }
        .foregroundStyle(MAYNTheme.textSecondary(colorScheme))
    }

    private func rowActionButton(symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}

private struct MainClipboardImageRecentRow: View {
    let item: ClipboardItemMeta
    let recordID: String
    let imageLoader: ImageBlobLoader
    let appIcons: AppIconResolver
    let isSelected: Bool
    var isHovering: Bool
    let onSelect: () -> Void
    let onCopy: () -> Void
    let onPin: () -> Void
    let onDelete: () -> Void
    var onReveal: (() -> Void)? = nil
    var quickShortcut: String? = nil
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            MainClipboardThumbnailView(
                recordID: recordID,
                imageLoader: imageLoader,
                width: 92,
                height: 62,
                maxDim: 192
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(item.customLabel ?? "Image")
                    .font(.callout)
                Text("\(item.preview) - \(CompactTimestamp.format(item.modified))")
                    .font(.caption)
                    .foregroundStyle(
                        MAYNSelectionLabelStyle.subtitle(
                            isSelected: isSelected,
                            scheme: colorScheme
                        )
                    )
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isHovering {
                ClipboardHistoryRowActions(
                    isSelected: isSelected,
                    onCopy: onCopy,
                    onPin: onPin,
                    onDelete: onDelete,
                    onReveal: onReveal,
                    quickShortcut: quickShortcut
                )
            }

            if ClipboardHistoryIconPresentation.hasSourceApp(item) {
                ClipboardHistoryIconView(
                    item: item,
                    fallbackSymbol: "photo",
                    appIcons: appIcons,
                    size: 28,
                    symbolFontSize: 15,
                    cornerRadius: 7
                )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: 82)
        .frame(maxWidth: .infinity, alignment: .leading)
        .maynSelectionBackground(
            isSelected: isSelected,
            isHovering: isHovering,
            shape: .rounded(10)
        )
        .foregroundStyle(MAYNTheme.textPrimary(colorScheme))
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                onCopy()
            }
        )
        .animation(MAYNMotion.normalAnimation(reduceMotion: reduceMotion), value: isHovering)
        .animation(MAYNMotion.normalAnimation(reduceMotion: reduceMotion), value: isSelected)
    }
}

private struct MainClipboardThumbnailView: View {
    let recordID: String
    let imageLoader: ImageBlobLoader
    let width: CGFloat
    let height: CGFloat
    let maxDim: Int
    @State private var image: NSImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(4)
            } else if failed {
                Image(systemName: "photo")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.tertiary)
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .frame(width: width, height: height)
        .background(MAYNTheme.elevated, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(MAYNTheme.subtleBorder, lineWidth: 1)
        )
        .task(id: "\(recordID)-\(maxDim)") {
            image = nil
            failed = false
            let loadedImage = await imageLoader.thumbnail(recordID: recordID, maxDim: maxDim)
            guard !Task.isCancelled else { return }
            image = loadedImage
            failed = loadedImage == nil
        }
    }
}
