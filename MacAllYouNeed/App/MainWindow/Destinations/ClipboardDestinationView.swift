import AppKit
import Core
import CoreFoundation
import FeatureCore
import Platform
import SwiftUI

struct ClipboardDestinationView: View {
    let controller: AppController
    @AppStorage("retention.maxAgeDays", store: AppGroupSettings.defaults) private var maxAgeDays = 30
    @AppStorage("autoPaste.behavior", store: AppGroupSettings.defaults) private var pasteBehavior = "pasteIntoFocused"
    @AppStorage("autoPaste.delayMs", store: AppGroupSettings.defaults) private var pasteDelay = 150
    @AppStorage(ClipboardFunctionTab.storageKey, store: AppGroupSettings.defaults) private var selectedTabRaw = ClipboardFunctionTab.history.rawValue
    @State private var blockedApps: [String] = ExcludedAppsStore.load()
    @State private var hotkeyMap: [HotkeyAction: [Platform.HotkeyDescriptor]] = HotkeyMapStore.defaultMap
    @State private var hotkeyRegistrationErrors: [HotkeyAction: String] = [:]
    @State private var historyItems: [ClipboardItemMeta] = []
    @State private var historySearch = ""
    @State private var historyPage = 0
    @State private var isHistoryLoading = false
    private static let historyPageSize = 20

    private var selectedTab: Binding<ClipboardFunctionTab> {
        Binding {
            ClipboardFunctionTab.storedSelection(selectedTabRaw)
        } set: { tab in
            selectedTabRaw = tab.rawValue
        }
    }

    var body: some View {
        FunctionPageShell(
            title: "Clipboard",
            subtitle: "History, ignored apps, and paste behavior for local clipboard memory.",
            selection: selectedTab,
            toolbar: {
                MainHeaderShortcutDisplay(
                    text: MainToolHeaderShortcutModel.display(
                        for: .clipboard,
                        hotkeys: hotkeyMap,
                        voiceSettings: VoiceActivationSettingsStore.load()
                    )
                )
            }
        ) {
            switch ClipboardFunctionTab.storedSelection(selectedTabRaw) {
            case .history:
                FunctionPageScrollContent {
                    clipboardHistorySection
                }
            case .rules:
                FunctionPageScrollContent {
                    clipboardRulesSection
                }
            case .settings:
                FunctionPageScrollContent {
                    clipboardSettingsSection
                }
            }
        }
        .onAppear {
            hotkeyMap = HotkeyMapStore.load()
            blockedApps = ExcludedAppsStore.load()
            reloadClipboardHistory()
        }
        .onReceive(NotificationCenter.default.publisher(for: .clipboardStoreDidChange)) { _ in
            reloadClipboardHistory()
        }
        .onChange(of: controller.clipboardReader.items.map(\.id.rawValue)) { _, _ in
            reloadClipboardHistory()
        }
        .onChange(of: historySearch) { _, _ in
            historyPage = 0
            reloadClipboardHistory()
        }
        .onChange(of: historyItems.map(\.id.rawValue)) { _, _ in
            clampClipboardHistoryPage()
        }
        .onChange(of: maxAgeDays) { _, _ in
            postRetentionSettingsChangedDarwin()
            reloadClipboardHistory()
        }
    }

    private var clipboardHistorySection: some View {
        Group {
            MAYNSection(title: "All items", subtitle: "Search and page through the full local clipboard history.") {
                let state = clipboardHistoryState
                ClipboardHistorySearchBar(
                    query: $historySearch,
                    resultText: state.totalItems == 1 ? "1 item" : "\(state.totalItems) items"
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
                    ForEach(Array(state.visibleItems.enumerated()), id: \.element.id.rawValue) { index, item in
                        if index > 0 { MAYNDivider() }
                        MainClipboardRecentRow(
                            item: item,
                            imageLoader: controller.clipboardDeps.imageLoader,
                            appIcons: controller.clipboardDeps.appIcons,
                            isSelected: controller.clipboardReader.selectedIDs.contains(item.id.rawValue),
                            onSelect: {
                                selectClipboardHistoryItem(item)
                            },
                            onCopy: {
                                copyClipboardHistoryItems(ids: [item.id.rawValue])
                            }
                        )
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
        MainClipboardHistoryPresentation.state(
            items: historyItems,
            query: "",
            requestedPage: historyPage,
            pageSize: Self.historyPageSize
        )
    }

    private var filteredClipboardHistoryItems: [ClipboardItemMeta] {
        clipboardHistoryState.filteredItems
    }

    private var visibleClipboardHistoryItems: [ClipboardItemMeta] {
        clipboardHistoryState.visibleItems
    }

    private var clipboardRulesSection: some View {
        MAYNSection(
            title: "Ignored Apps",
            subtitle: "Clipboard content copied from these apps will never be saved to history."
        ) {
            BundleIDExclusionEditor(bundleIDs: $blockedApps) { ExcludedAppsStore.save($0) }
        }
    }

    private var clipboardSettingsSection: some View {
        Group {
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

    private func reloadClipboardHistory() {
        guard let store = controller.clipboardReader.store else {
            historyItems = controller.clipboardReader.items
            return
        }

        let params = ClipboardHistoryWindow.listParameters()
        let limit = params.fetchLimit
        let trimmedSearch = historySearch.trimmingCharacters(in: .whitespacesAndNewlines)
        let worker = controller.clipboardDeps.clipboardWorker
        isHistoryLoading = true
        Task {
            let fuzzyEnabled = AppGroupSettings.defaults.object(forKey: "search.fuzzy") as? Bool ?? false
            let result: Result<[ClipboardItemMeta], Error>
            if trimmedSearch.isEmpty {
                let items = await worker.loadHistoryMetas(
                    query: nil,
                    limit: limit,
                    fuzzyEnabled: false
                )
                result = .success(LocalClipboardReader.deduplicate(items, limit: limit))
            } else {
                let items = await worker.loadHistoryMetas(
                    query: trimmedSearch,
                    limit: limit,
                    fuzzyEnabled: fuzzyEnabled
                )
                result = .success(items)
            }

            switch result {
            case let .success(fetched):
                historyItems = fetched
            case .failure:
                historyItems = controller.clipboardReader.items
            }
            isHistoryLoading = false
            clampClipboardHistoryPage()
        }
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

private struct ClipboardHistorySearchBar: View {
    @Binding var query: String
    let resultText: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            TextField("Search all clipboard items", text: $query)
                .textFieldStyle(.plain)

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Text(resultText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MainClipboardRecentRow: View {
    let item: ClipboardItemMeta
    let imageLoader: ImageBlobLoader
    let appIcons: AppIconResolver
    let isSelected: Bool
    let onSelect: () -> Void
    let onCopy: () -> Void

    var body: some View {
        switch MainClipboardItemPresentation.previewKind(for: item) {
        case let .imageThumbnail(recordID):
            MainClipboardImageRecentRow(
                item: item,
                recordID: recordID,
                imageLoader: imageLoader,
                appIcons: appIcons,
                isSelected: isSelected,
                onSelect: onSelect,
                onCopy: onCopy
            )
        case let .symbol(symbol):
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.customLabel ?? item.preview)
                        .font(.callout)
                        .lineLimit(2)
                    Text(CompactTimestamp.format(item.modified))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                ClipboardHistoryIconView(
                    item: item,
                    fallbackSymbol: symbol,
                    appIcons: appIcons,
                    size: 28,
                    symbolFontSize: 15,
                    cornerRadius: 7
                )
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(minHeight: 62)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowBackground)
            .contentShape(Rectangle())
            .onTapGesture(perform: onSelect)
            .simultaneousGesture(
                TapGesture(count: 2).onEnded {
                    onCopy()
                }
            )
        }
    }

    private var rowBackground: Color {
        isSelected ? Color.primary.opacity(0.10) : Color.clear
    }
}

private struct MainClipboardImageRecentRow: View {
    let item: ClipboardItemMeta
    let recordID: String
    let imageLoader: ImageBlobLoader
    let appIcons: AppIconResolver
    let isSelected: Bool
    let onSelect: () -> Void
    let onCopy: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

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
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

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
        .background(rowBackground)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                onCopy()
            }
        )
        .animation(MAYNMotion.normalAnimation(reduceMotion: reduceMotion), value: isHovering)
        .animation(MAYNMotion.normalAnimation(reduceMotion: reduceMotion), value: isSelected)
        .onHover { isHovering = $0 }
    }

    private var rowBackground: Color {
        if isSelected { return Color.primary.opacity(0.10) }
        if isHovering { return MAYNTheme.hover }
        return .clear
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
            await MainActor.run {
                image = loadedImage
                failed = loadedImage == nil
            }
        }
    }
}
