import AppKit
import Core
import Platform
import SwiftUI

struct DownloadsListView: View {
    @Bindable var vm: DownloaderViewModel
    var filter: DownloadsListFilter = .all
    var surface: DownloadsListSurface = .main
    var onPasteURL: (() -> Void)?
    var onAddURL: (() -> Void)?
    @FocusState private var listFocused: Bool
    @State private var keyMonitor: NSEventMonitorHandle? = nil
    @State private var expandedGroups: Set<String> = []
    @State private var showAllInGroup: Set<String> = []
    @State private var deleteGroup: DownloadCollectionGrouping.Group?
    private let visibleItemCap = 5

    var body: some View {
        VStack(spacing: 0) {
            if surface == .main {
                listHeader
                MAYNDivider()
                if let warning = vm.cookieWarning {
                    cookieWarningBanner(warning)
                    MAYNDivider()
                }
                if vm.interruptedRecoveryCount > 0, filter != .completed {
                    interruptedBanner
                    MAYNDivider()
                }
                if DownloadsQueuePresentation.showsFailedBanner(rows: vm.rows, filter: filter) {
                    failedBanner
                    MAYNDivider()
                }
            }

            if visibleRows.isEmpty {
                DownloadsEmptyStateView(
                    model: DownloadsEmptyStatePresentation.model(for: filter),
                    onPasteURL: pasteURL,
                    onAddURL: addURL
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(listItems) { item in
                            switch item {
                            case let .group(group):
                                groupSection(group)
                            case let .single(record):
                                row(for: record, indent: false)
                            }
                        }
                    }
                }
            }
        }
        .sheet(item: $deleteGroup) { group in
            DownloadCollectionDeleteSheet(
                title: group.title,
                itemCount: group.totalCount,
                onCancel: { deleteGroup = nil },
                onRemoveListOnly: {
                    deleteGroup = nil
                    Task { await vm.deleteCollection(id: group.id, deleteFiles: false) }
                },
                onRemoveWithFiles: {
                    deleteGroup = nil
                    Task { await vm.deleteCollection(id: group.id, deleteFiles: true) }
                }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(surface == .main ? Color.clear : MAYNTheme.window)
        .focusable()
        .focusEffectDisabled()
        .focused($listFocused)
        .onAppear {
            listFocused = true
            installKeyMonitor()
            if expandedGroups.isEmpty {
                if surface == .main {
                    expandedGroups = Set(listItems.compactMap { item in
                        if case let .group(group) = item { return group.id }
                        return nil
                    })
                }
            }
        }
        .onDisappear {
            keyMonitor = nil
            vm.selectedIDs = []
            vm.anchorID = nil
        }
        .task { await vm.refresh() }
    }

    private var visibleRows: [DownloadRecord] {
        DownloadsQueuePresentation.visibleRows(vm.rows, filter: filter)
    }

    private var listItems: [DownloadCollectionGrouping.ListItem] {
        DownloadCollectionGrouping.items(from: visibleRows)
    }

    @ViewBuilder
    private func groupSection(_ group: DownloadCollectionGrouping.Group) -> some View {
        let expanded = expandedGroups.contains(group.id)
        let progress = DownloadCollectionGrouping.aggregateProgress(
            records: group.records,
            liveProgress: vm.liveProgress
        )
        let speed = DownloadCollectionGrouping.aggregateSpeedBytes(
            records: group.records,
            liveProgress: vm.liveProgress
        )
        let speedText = speed > 0
            ? "\(ByteCountFormatter.string(fromByteCount: Int64(speed), countStyle: .file))/s"
            : nil
        let running = group.records.filter { $0.state == .running }
        let etaText: String? = {
            guard running.count == 1,
                  let eta = vm.liveProgress[running[0].id.rawValue]?.etaSeconds,
                  eta > 0 else { return nil }
            return "ETA \(eta / 60):\(String(format: "%02d", eta % 60))"
        }()
        let hasActive = group.records.contains { $0.state == .running || $0.state == .queued }
        let resumable = group.records.contains { $0.state == .paused || $0.state == .failed }

        DownloadCollectionGroupHeader(
            group: group,
            progress: progress,
            speedText: speedText,
            etaText: etaText,
            isExpanded: expanded,
            showsPauseAll: hasActive,
            showsResumeAll: !hasActive && resumable,
            onToggleExpanded: {
                if expanded { expandedGroups.remove(group.id) } else { expandedGroups.insert(group.id) }
            },
            onPauseAll: { Task { await vm.pauseCollection(id: group.id) } },
            onResumeAll: { Task { await vm.resumeCollection(id: group.id) } },
            onDelete: { deleteGroup = group }
        )

        if expanded {
            let showAll = showAllInGroup.contains(group.id)
            let visibleChildren = showAll ? group.records : Array(group.records.prefix(visibleItemCap))
            ForEach(visibleChildren, id: \.id) { record in
                row(for: record, indent: true)
            }
            if !showAll, group.records.count > visibleItemCap {
                Button("Show \(group.records.count - visibleItemCap) more") {
                    showAllInGroup.insert(group.id)
                }
                .font(.caption.weight(.medium))
                .padding(.leading, 32)
                .padding(.vertical, 8)
            }
        }
    }

    private func row(for record: DownloadRecord, indent: Bool) -> some View {
        DownloadJobRow(
            model: DownloadJobRowModel(
                record: record,
                progress: vm.liveProgress[record.id.rawValue],
                statusText: vm.liveStatus[record.id.rawValue]
            ),
            isSelected: vm.selectedIDs.contains(record.id.rawValue),
            isCompact: surface == .commandCenter,
            onTap: { handleTap(id: record.id.rawValue) },
            onPrimaryAction: { performPrimaryAction(for: record) },
            onDelete: { Task { await vm.delete(ids: [record.id]) } }
        )
        .padding(.leading, indent ? 16 : 0)
    }

    private var interruptedBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "pause.circle.fill")
                .foregroundStyle(MAYNTheme.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(vm.interruptedRecoveryCount) downloads were interrupted")
                    .font(.callout.weight(.semibold))
                Text("Resume all to continue from partial files.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            MAYNButton("Resume all") {
                Task { await vm.resumeInterruptedDownloads() }
            }
        }
        .padding(.horizontal, MAYNControlMetrics.rowHorizontalPadding)
        .padding(.vertical, MAYNControlMetrics.rowVerticalPadding)
        .background(MAYNTheme.warning.opacity(0.08))
    }

    // MARK: - Header

    private var listHeader: some View {
        HStack(spacing: 10) {
            Text("Downloads")
                .font(.callout.weight(.semibold))
            if !visibleRows.isEmpty {
                Text("\(visibleRows.count)")
                    .font(.system(.caption, design: .monospaced).weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .frame(height: 24)
                    .background(MAYNTheme.elevated, in: Capsule())
                    .overlay(Capsule().stroke(MAYNTheme.subtleBorder, lineWidth: 1))
            }
            Spacer()
            if let actionTitle = DownloadsQueuePresentation.headerActionTitle(rows: vm.rows, filter: filter) {
                MAYNButton(actionTitle, height: MAYNControlMetrics.controlHeight) {
                    performHeaderAction()
                }
            }
        }
        .padding(.horizontal, MAYNControlMetrics.rowHorizontalPadding)
        .padding(.vertical, 11)
    }

    private var failedBanner: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(MAYNTheme.danger)
            VStack(alignment: .leading, spacing: 2) {
                Text("A download failed")
                    .font(.callout.weight(.semibold))
                Text("Failed rows show captured yt-dlp errors inline when available. Hover a failed row for details.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 12)
            MAYNButton("Retry all") {
                Task { await vm.retryFailed(in: visibleRows) }
            }
        }
        .padding(.horizontal, MAYNControlMetrics.rowHorizontalPadding)
        .padding(.vertical, MAYNControlMetrics.rowVerticalPadding)
        .background(MAYNTheme.danger.opacity(0.08))
    }

    private func cookieWarningBanner(_ warning: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(MAYNTheme.warning)
            Text(warning)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            MAYNButton("Open Chrome", height: HotkeyChipPresentation.compactHeight) {
                NSWorkspace.shared.open(URL(string: "https://www.youtube.com")!)
            }
            Button { vm.dismissCookieWarning() } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, MAYNControlMetrics.rowHorizontalPadding)
        .padding(.vertical, 7)
        .background(MAYNTheme.warning.opacity(0.08))
    }

    // MARK: - Actions

    private func pasteURL() {
        if let onPasteURL {
            onPasteURL()
        } else {
            Task { await vm.enqueueClipboardURL() }
        }
    }

    private func addURL() {
        onAddURL?()
    }

    private func performHeaderAction() {
        switch filter {
        case .all, .activeQueue:
            Task { await vm.retryFailed(in: visibleRows) }
        case .completed:
            openDefaultDownloadFolder()
        }
    }

    private func performPrimaryAction(for record: DownloadRecord) {
        switch record.state {
        case .running:
            Task { await vm.pause(id: record.id) }
        case .paused:
            Task { await vm.resume(id: record.id) }
        case .queued:
            Task { await vm.cancel(id: record.id) }
        case .completed:
            openFolder(for: record)
        case .failed:
            Task { await vm.retry(record: record) }
        }
    }

    private func openFolder(for record: DownloadRecord) {
        openFinderFolder(DownloadFolderOpenTarget.completedRecord(record).folderURL)
    }

    private func openDefaultDownloadFolder() {
        let downloadDir = AppGroupSettings.defaults.string(forKey: "downloadDirectory") ?? ""
        openFinderFolder(DownloadFolderOpenTarget.defaultDownloadFolder(downloadDir: downloadDir).folderURL)
    }

    private func openFinderFolder(_ folderURL: URL) {
        NSWorkspace.shared.open(folderURL)
    }

    // MARK: - Key handling

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        claimKeyWindow()
        let vm = vm
        keyMonitor = NSEventMonitorHandle(local: .keyDown) { event in
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let isCommand = modifiers.contains(.command)
            let character = event.charactersIgnoringModifiers ?? ""
            let isDeleteKey = event.keyCode == 51 || event.keyCode == 117
                || character == "\u{7F}" || character == "\u{F728}"

            if MAYNTextEditingShortcutPolicy.shouldYieldToFocusedTextInput(
                isTextEditingFirstResponder: MAYNTextEditingShortcutPolicy.isTextEditingFirstResponder(
                    in: event.window ?? NSApp.keyWindow
                ),
                keyEquivalent: character,
                modifiers: event.modifierFlags
            ) {
                return event
            }

            if isCommand, isDeleteKey {
                guard !vm.selectedIDs.isEmpty else { return event }
                let ids = visibleRows.filter { vm.selectedIDs.contains($0.id.rawValue) }.map(\.id)
                vm.selectedIDs = []
                vm.anchorID = nil
                Task { @MainActor in await vm.delete(ids: ids) }
                return nil
            }
            if isCommand, character == "a" {
                DownloadsListSelectionController.applySelectAll(
                    visibleRows: visibleRows,
                    selectedIDs: &vm.selectedIDs,
                    anchorID: &vm.anchorID
                )
                return nil
            }
            if isCommand, character == "v" {
                pasteURL()
                return nil
            }
            if event.keyCode == 53 {
                let consumed = DownloadsListSelectionController.applyEscape(
                    selectedIDs: &vm.selectedIDs,
                    anchorID: &vm.anchorID
                )
                return consumed ? nil : event
            }
            return event
        }
    }

    private func claimKeyWindow() {
        guard surface == .commandCenter else { return }
        // Do NOT call NSApp.activate here. When a full-screen app lives on
        // one Space and our app's other windows (main window, extra
        // NSStatusBarWindow instances on the non-fullscreen display) live on
        // the desktop Space, activating pulls macOS to that desktop Space,
        // dragging the popover along with it. The popover is already key
        // when shown by AppStatusItemController; just re-assert key on the
        // popover window itself in case SwiftUI shifted first-responder.
        for window in NSApp.windows {
            let name = String(describing: type(of: window))
            if name.contains("Popover") {
                window.makeKey()
                return
            }
        }
    }

    // MARK: - Selection

    private func handleTap(id: String) {
        listFocused = true
        claimKeyWindow()
        let flags = NSApp.currentEvent?.modifierFlags ?? []
        DownloadsListSelectionController.applyTap(
            id: id,
            visibleRows: visibleRows,
            selectedIDs: &vm.selectedIDs,
            anchorID: &vm.anchorID,
            modifiers: flags
        )
    }
}
