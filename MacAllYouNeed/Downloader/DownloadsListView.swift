import AppKit
import Core
import os
import Platform
import SwiftUI

private let downloadsListLog = Logger(subsystem: Logging.subsystem(for: "downloader"), category: "list")

struct DownloadsListView: View {
    @Bindable var vm: DownloaderViewModel
    @AppStorage("downloadCookieMode", store: AppGroupSettings.defaults) private var cookieMode = "browser_auto"
    @AppStorage("downloadDirectory", store: AppGroupSettings.defaults) private var downloadDir = ""
    var filter: DownloadsListFilter = .all
    var surface: DownloadsListSurface = .main
    var onPasteURL: (() -> Void)?
    var onAddURL: (() -> Void)?
    @FocusState private var listFocused: Bool
    @State private var keyMonitor: NSEventMonitorHandle? = nil
    @State private var expandedGroups: Set<String> = []
    @State private var showAllInGroup: Set<String> = []
    @State private var deleteGroup: DownloadCollectionGrouping.Group?
    @State private var deleteRecord: DownloadRecord?
    @State private var searchQuery = ""
    @State private var viewMode: DownloadsPageViewMode = .grouped
    @State private var statusFilter: DownloadsStatusFilter = .all
    @State private var collectionItemFilters: [String: DownloadCollectionItemFilter] = [:]
    @State private var pendingDeleteFiles = false
    @State private var seenRowIDs: Set<String> = []
    @State private var didSeedSeenRows = false
    private let visibleItemCap = 5
    private let listInset: CGFloat = MAYNControlMetrics.rowControlSpacing
    private let cardInnerPadding: CGFloat = MAYNControlMetrics.rowControlSpacing

    var body: some View {
        let visibleRows = vm.presentation.visibleRows(for: filter)
        let filteredRows = DownloadsPagePresentation.filterRows(
            visibleRows,
            statusFilter: statusFilter,
            query: searchQuery
        )
        let listItems = DownloadsPagePresentation.listItems(from: filteredRows, mode: surface == .main ? viewMode : .grouped)
        let shouldShowThumbnails = vm.presentation.shouldShowThumbnails(for: filter)
        let metrics = DownloadsPagePresentation.metrics(rows: visibleRows)
        let hasGroups = listItems.contains {
            if case .group = $0 { return true }
            return false
        }

        Group {
            if surface == .main {
                mainSurfaceBody(
                    visibleRows: visibleRows,
                    filteredRows: filteredRows,
                    listItems: listItems,
                    metrics: metrics,
                    hasGroups: hasGroups,
                    showsThumbnail: shouldShowThumbnails
                )
            } else {
                commandCenterBody(
                    visibleRows: visibleRows,
                    listItems: listItems,
                    showsThumbnail: shouldShowThumbnails
                )
            }
        }
        .sheet(item: $deleteRecord) { record in
            DownloadCollectionDeleteSheet(
                title: record.videoTitle ?? record.title,
                itemLabel: "1 video",
                statusLabel: DownloadCollectionPresentation.singleStatus(for: record).label,
                locationLabel: DownloadCollectionPresentation.singleLocationLabel(
                    for: record,
                    downloadDir: downloadDir
                ),
                initialDeleteFiles: pendingDeleteFiles,
                onCancel: { deleteRecord = nil },
                onConfirm: { deleteFiles in
                    deleteRecord = nil
                    Task {
                        if deleteFiles {
                            await vm.deleteWithFiles([record])
                        } else {
                            await vm.delete(ids: [record.id])
                        }
                    }
                }
            )
        }
        .sheet(item: $deleteGroup) { group in
            let progress = vm.presentation.groupProgress(for: group.id)
                ?? DownloadCollectionGrouping.aggregateProgress(
                    records: group.records,
                    liveProgress: vm.liveProgress
                )
            let cachedState = vm.presentation.groupState(for: group.id)
            let hasActive = cachedState?.hasActive ?? group.records.contains { $0.state == .running || $0.state == .queued }
            DownloadCollectionDeleteSheet(
                title: group.title,
                itemLabel: DownloadCollectionPresentation.deleteSheetItemLabel(
                    count: group.totalCount,
                    kind: group.kind
                ),
                statusLabel: DownloadCollectionPresentation.deleteSheetStatus(
                    for: group,
                    hasActive: hasActive,
                    progress: progress
                ),
                locationLabel: DownloadCollectionPresentation.locationLabel(
                    for: group,
                    downloadDir: downloadDir
                ),
                initialDeleteFiles: pendingDeleteFiles,
                onCancel: { deleteGroup = nil },
                onConfirm: { deleteFiles in
                    deleteGroup = nil
                    Task { await vm.deleteCollection(id: group.id, deleteFiles: deleteFiles) }
                }
            )
        }
        .modifier(DownloadsListSurfaceFrame(surface: surface))
        .background(surface == .main ? Color.clear : MAYNTheme.window)
        .focusable()
        .focusEffectDisabled()
        .focused($listFocused)
        .onAppear {
            listFocused = true
            installKeyMonitor()
            clearStaleExtensionCookieWarningIfNeeded()
            if !didSeedSeenRows {
                seenRowIDs = Set(visibleRowsForCurrentFilter().map(\.id.rawValue))
                didSeedSeenRows = true
            }
        }
        .onChange(of: cookieMode) { _, _ in
            clearStaleExtensionCookieWarningIfNeeded()
        }
        .onDisappear {
            keyMonitor = nil
            vm.selectedIDs = []
            vm.anchorID = nil
        }
    }

    @ViewBuilder
    private func mainSurfaceBody(
        visibleRows: [DownloadRecord],
        filteredRows: [DownloadRecord],
        listItems: [DownloadCollectionGrouping.ListItem],
        metrics: DownloadsPageMetrics,
        hasGroups: Bool,
        showsThumbnail: Bool
    ) -> some View {
        VStack(spacing: 0) {
            DownloadsPageToolbar(
                metrics: metrics,
                statusFilter: $statusFilter,
                searchQuery: $searchQuery,
                onOpenFolder: openDefaultDownloadFolder
            )
            DownloadsSurfaceDivider()
            mainStatusBanners(metrics: metrics)

            if visibleRows.isEmpty {
                DownloadsEmptyStateView(
                    model: DownloadsEmptyStatePresentation.model(for: filter),
                    onPasteURL: pasteURL,
                    onAddURL: addURL
                )
                .padding(.vertical, 24)
            } else {
                VStack(spacing: 0) {
                    DownloadsMetricsBar(metrics: metrics)
                        .padding(.horizontal, listInset)
                        .padding(.top, 16)
                        .padding(.bottom, 4)

                    DownloadsSectionHeading(
                        title: DownloadsPagePresentation.sectionTitle(mode: viewMode, hasGroups: hasGroups),
                        subtitle: sectionSubtitle(mode: viewMode, hasGroups: hasGroups),
                        viewMode: $viewMode
                    )

                    if filteredRows.isEmpty {
                        searchEmptyState
                    } else {
                        downloadRows(listItems: listItems, showsThumbnail: showsThumbnail)
                    }
                }
            }
        }
        .background(MAYNTheme.panel.opacity(0.92), in: RoundedRectangle(cornerRadius: MAYNControlMetrics.panelRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MAYNControlMetrics.panelRadius, style: .continuous)
                .stroke(MAYNTheme.subtleBorder, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func commandCenterBody(
        visibleRows: [DownloadRecord],
        listItems: [DownloadCollectionGrouping.ListItem],
        showsThumbnail: Bool
    ) -> some View {
        VStack(spacing: 0) {
            statusBanners
            if visibleRows.isEmpty {
                DownloadsEmptyStateView(
                    model: DownloadsEmptyStatePresentation.model(for: filter),
                    onPasteURL: pasteURL,
                    onAddURL: addURL
                )
            } else {
                downloadRows(listItems: listItems, showsThumbnail: showsThumbnail)
            }
        }
    }

    @ViewBuilder
    private func mainStatusBanners(metrics: DownloadsPageMetrics) -> some View {
        if let warning = vm.cookieWarning {
            cookieWarningBanner(warning)
            DownloadsSurfaceDivider()
        }
        if vm.interruptedRecoveryCount > 0, filter != .completed {
            interruptedBanner
            DownloadsSurfaceDivider()
        }
        if metrics.failedCount > 0 {
            DownloadsFailedBanner(
                failedCount: metrics.failedCount,
                onShowFailed: { statusFilter = .failed },
                onRetryFailed: {
                    Task { await vm.retryFailed(in: visibleRowsForCurrentFilter()) }
                }
            )
            DownloadsSurfaceDivider()
        }
    }

    @ViewBuilder
    private var statusBanners: some View {
        if let warning = vm.cookieWarning {
            cookieWarningBanner(warning)
            DownloadsSurfaceDivider()
        }
        if vm.interruptedRecoveryCount > 0, filter != .completed {
            interruptedBanner
            DownloadsSurfaceDivider()
        }
        if vm.presentation.hasFailed(for: filter) {
            commandCenterFailedBanner
            DownloadsSurfaceDivider()
        }
    }

    private var commandCenterFailedBanner: some View {
        let failedCount = visibleRowsForCurrentFilter().filter { $0.state == .failed }.count
        return CommandCenterAttentionStrip(
            title: "Review \(max(failedCount, 1)) downloads",
            detail: "Some videos could not be downloaded. Retry failed items from the footer."
        )
    }

    private var searchEmptyState: some View {
        VStack(spacing: 8) {
            Text("No matching downloads")
                .font(.callout.weight(.semibold))
            Text("Try a different search term.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, listInset)
    }

    private func sectionSubtitle(mode: DownloadsPageViewMode, hasGroups: Bool) -> String {
        switch mode {
        case .grouped where hasGroups:
            "Playlist downloads are grouped as one card. Expand a collection only when you need item-level control."
        case .grouped:
            "Downloads appear here as they are added."
        case .list:
            "Flat list of every download with thumbnails and file details."
        }
    }

    private func collectionItemFilter(for groupID: String) -> DownloadCollectionItemFilter {
        collectionItemFilters[groupID] ?? .all
    }

    private func visibleRowsForCurrentFilter() -> [DownloadRecord] {
        vm.presentation.visibleRows(for: filter)
    }

    @ViewBuilder
    private func downloadRows(listItems: [DownloadCollectionGrouping.ListItem], showsThumbnail: Bool) -> some View {
        let rows = LazyVStack(spacing: 14) {
            ForEach(listItems) { item in
                switch item {
                case let .group(group):
                    groupSection(group, showsThumbnail: showsThumbnail)
                case let .single(record):
                    if surface == .main {
                        singleSection(record, showsThumbnail: showsThumbnail)
                    } else {
                        row(for: record, indent: false, showsThumbnail: showsThumbnail)
                    }
                }
            }
        }
        .padding(.horizontal, surface == .main ? listInset : 0)
        .padding(.bottom, surface == .main ? listInset : 0)

        if surface == .commandCenter {
            ScrollView {
                rows
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            rows
        }
    }

    @ViewBuilder
    private func groupSection(_ group: DownloadCollectionGrouping.Group, showsThumbnail: Bool) -> some View {
        let expanded = expandedGroups.contains(group.id)
        let progress = vm.presentation.groupProgress(for: group.id)
            ?? DownloadCollectionGrouping.aggregateProgress(
                records: group.records,
                liveProgress: vm.liveProgress
            )
        let speed = vm.presentation.groupSpeed(for: group.id)
            ?? DownloadCollectionGrouping.aggregateSpeedBytes(
                records: group.records,
                liveProgress: vm.liveProgress
            )
        let cachedState = vm.presentation.groupState(for: group.id)
        let speedText = speed > 0
            ? "\(ByteCountFormatter.string(fromByteCount: Int64(speed), countStyle: .file))/s"
            : nil
        let etaText: String? = {
            guard cachedState?.runningCount == 1,
                  let running = group.records.first(where: { $0.state == .running }),
                  let eta = vm.liveProgress[running.id.rawValue]?.etaSeconds,
                  eta > 0 else { return nil }
            return "ETA \(eta / 60):\(String(format: "%02d", eta % 60))"
        }()
        let hasActive = cachedState?.hasActive ?? group.records.contains { $0.state == .running || $0.state == .queued }
        let resumable = cachedState?.resumable ?? group.records.contains { $0.state == .paused || $0.state == .failed }
        let locationLabel = DownloadCollectionPresentation.locationLabel(for: group, downloadDir: downloadDir)
        let collectionStatus = DownloadCollectionPresentation.status(
            for: group,
            hasActive: hasActive,
            progress: progress
        )

        VStack(spacing: 0) {
            DownloadCollectionGroupHeader(
                group: group,
                progress: progress,
                speedText: speedText,
                etaText: etaText,
                locationLabel: locationLabel,
                collectionStatus: collectionStatus,
                hasActive: hasActive,
                isExpanded: expanded,
                isCompact: surface == .commandCenter,
                showsPauseAll: hasActive,
                showsResumeAll: !hasActive && resumable,
                onToggleExpanded: {
                    if expanded { expandedGroups.remove(group.id) } else { expandedGroups.insert(group.id) }
                },
                onOpenFolder: { openFolder(for: group) },
                onPauseAll: { Task { await vm.pauseCollection(id: group.id) } },
                onResumeAll: { Task { await vm.resumeCollection(id: group.id) } },
                onRetryFailed: { Task { await vm.retryFailed(in: group.records) } },
                onCopySourceURL: { copySourceURL(for: group) },
                onRemoveFromList: {
                    pendingDeleteFiles = false
                    deleteGroup = group
                },
                onMoveFilesToTrash: {
                    pendingDeleteFiles = true
                    deleteGroup = group
                }
            )

            if expanded {
                DownloadsSurfaceDivider()
                expandedGroupBody(
                    group,
                    showsThumbnail: showsThumbnail,
                    hasActive: hasActive,
                    progress: progress
                )
            }
        }
        .background(
            RoundedRectangle(cornerRadius: MAYNControlMetrics.cardRadius, style: .continuous)
                .fill(MAYNTheme.window)
        )
        .clipShape(RoundedRectangle(cornerRadius: MAYNControlMetrics.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MAYNControlMetrics.cardRadius, style: .continuous)
                .stroke(MAYNTheme.subtleBorder, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func expandedGroupBody(
        _ group: DownloadCollectionGrouping.Group,
        showsThumbnail: Bool,
        hasActive: Bool,
        progress: Double
    ) -> some View {
        let itemFilter = collectionItemFilter(for: group.id)
        let filteredRecords = group.records.filter { itemFilter.includes($0.state) }
        let showAll = showAllInGroup.contains(group.id)
        let visibleChildren = showAll ? filteredRecords : Array(filteredRecords.prefix(visibleItemCap))

        VStack(alignment: .leading, spacing: 0) {
            DownloadCollectionExpandedToolbar(
                itemFilter: itemFilter,
                onSelectFilter: { collectionItemFilters[group.id] = $0 },
                onCopySourceURL: { copySourceURL(for: group) }
            )

            ScrollView {
                VStack(spacing: 0) {
                    if visibleChildren.isEmpty {
                        Text("No \(itemFilter.title.lowercased()) downloads in this collection.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, cardInnerPadding)
                            .padding(.vertical, 16)
                    } else {
                        ForEach(Array(visibleChildren.enumerated()), id: \.element.id) { index, record in
                            collectionItemRow(
                                for: record,
                                showsThumbnail: showsThumbnail,
                                showsDivider: index < visibleChildren.count - 1
                            )
                        }
                    }

                    if !showAll, filteredRecords.count > visibleItemCap {
                        DownloadsSurfaceDivider()
                        Button("Show \(filteredRecords.count - visibleItemCap) more") {
                            showAllInGroup.insert(group.id)
                        }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, cardInnerPadding)
                        .padding(.vertical, 12)
                    }
                }
            }
            .frame(maxHeight: 420)
            .background(MAYNTheme.window, in: RoundedRectangle(cornerRadius: MAYNControlMetrics.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: MAYNControlMetrics.cardRadius, style: .continuous)
                    .stroke(MAYNTheme.subtleBorder, lineWidth: 1)
            )
            .padding(.horizontal, cardInnerPadding)
            .padding(.bottom, cardInnerPadding)
        }
        .padding(.top, 4)
        .background(MAYNTheme.elevated.opacity(0.35))
    }

    private func collectionItemRow(
        for record: DownloadRecord,
        showsThumbnail: Bool,
        showsDivider: Bool
    ) -> some View {
        DownloadCollectionItemRow(
            record: record,
            model: DownloadJobRowModel(
                record: record,
                progress: vm.liveProgress[record.id.rawValue],
                statusText: vm.liveStatus[record.id.rawValue]
            ),
            isSelected: vm.selectedIDs.contains(record.id.rawValue),
            isCompact: surface == .commandCenter,
            showsThumbnail: showsThumbnail,
            showsDivider: showsDivider,
            onTap: { handleTap(id: record.id.rawValue) },
            onPrimaryAction: { performPrimaryAction(for: record) },
            onReveal: { openFolder(for: record) },
            onDelete: { Task { await vm.delete(ids: [record.id]) } }
        )
    }

    @ViewBuilder
    private func singleSection(_ record: DownloadRecord, showsThumbnail _: Bool) -> some View {
        let model = DownloadJobRowModel(
            record: record,
            progress: vm.liveProgress[record.id.rawValue],
            statusText: vm.liveStatus[record.id.rawValue]
        )
        let locationLabel = DownloadCollectionPresentation.singleLocationLabel(
            for: record,
            downloadDir: downloadDir
        )

        DownloadSingleCardHeader(
            record: record,
            model: model,
            locationLabel: locationLabel,
            isCompact: surface == .commandCenter,
            onPrimaryAction: { performPrimaryAction(for: record) },
            onReveal: { openFolder(for: record) },
            onDelete: {
                pendingDeleteFiles = false
                deleteRecord = record
            }
        )
        .background(
            RoundedRectangle(cornerRadius: MAYNControlMetrics.cardRadius, style: .continuous)
                .fill(MAYNTheme.window)
        )
        .clipShape(RoundedRectangle(cornerRadius: MAYNControlMetrics.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MAYNControlMetrics.cardRadius, style: .continuous)
                .stroke(MAYNTheme.subtleBorder, lineWidth: 1)
        )
    }

    private func row(for record: DownloadRecord, indent: Bool, showsThumbnail: Bool) -> some View {
        let rowID = record.id.rawValue
        let isNew = didSeedSeenRows && !seenRowIDs.contains(rowID)
        return DownloadJobRow(
            model: DownloadJobRowModel(
                record: record,
                progress: vm.liveProgress[record.id.rawValue],
                statusText: vm.liveStatus[record.id.rawValue]
            ),
            isSelected: vm.selectedIDs.contains(rowID),
            isCompact: surface == .commandCenter,
            showsThumbnail: showsThumbnail,
            isNewlyInserted: isNew,
            onEntranceComplete: { seenRowIDs.insert(rowID) },
            onTap: { handleTap(id: rowID) },
            onPrimaryAction: { performPrimaryAction(for: record) },
            onDelete: { Task { await vm.delete(ids: [record.id]) } }
        )
        .padding(.leading, indent ? 10 : 0)
        .padding(.trailing, indent ? 6 : 0)
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

    private func cookieWarningBanner(_ warning: String) -> some View {
        let extensionGuidance = warning.localizedCaseInsensitiveContains("extension")
            || warning.localizedCaseInsensitiveContains("chrome companion")
            || cookieMode == "extension_only"
        return HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(MAYNTheme.warning)
            Text(warning)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if extensionGuidance {
                MAYNButton("Use Browser Auto", height: HotkeyChipPresentation.compactHeight) {
                    cookieMode = "browser_auto"
                    vm.dismissCookieWarning()
                }
                MAYNButton("Open Companion sync", height: HotkeyChipPresentation.compactHeight) {
                    _ = openInGoogleChrome("http://127.0.0.1:18765/cookie-sync-landing")
                }
                MAYNButton("Install Companion", height: HotkeyChipPresentation.compactHeight) {
                    _ = openInGoogleChrome("chrome://extensions")
                }
            } else {
                MAYNButton("Open settings", height: HotkeyChipPresentation.compactHeight) {
                    NotificationCenter.default.post(name: .mainWindowSettingsRequested, object: "downloads")
                }
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

    private func copySourceURL(for record: DownloadRecord) {
        let candidate = record.pageURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let url = candidate.isEmpty ? record.url : candidate
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url, forType: .string)
        CopyHUD.show("Copied URL", symbol: "link")
    }

    private func copySourceURL(for group: DownloadCollectionGrouping.Group) {
        guard let url = DownloadCollectionPresentation.sourceURL(for: group) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url, forType: .string)
        CopyHUD.show("Copied URL", symbol: "link")
    }

    private func openFolder(for record: DownloadRecord) {
        CopyHUD.show("Opening folder", symbol: "folder")
        let target = DownloadFolderOpenTarget.forRecord(
            record,
            downloadDir: downloadDir,
            resolvedDestinationPath: vm.resolvedDestinationPath(for: record)
        )
        openInFinder(target)
    }

    private func openFolder(for group: DownloadCollectionGrouping.Group) {
        CopyHUD.show("Opening folder", symbol: "folder")
        openInFinder(DownloadFolderOpenTarget.group(group, downloadDir: downloadDir))
    }

    private func openDefaultDownloadFolder() {
        openInFinder(DownloadFolderOpenTarget.defaultDownloadFolder(downloadDir: downloadDir))
    }

    private func openInFinder(_ target: DownloadFolderOpenTarget) {
        let url = target.selectionURL
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
            return
        }
        if url.hasDirectoryPath || url.pathExtension.isEmpty {
            NSWorkspace.shared.open(url)
            return
        }
        let parent = url.deletingLastPathComponent()
        if FileManager.default.fileExists(atPath: parent.path) {
            NSWorkspace.shared.activateFileViewerSelecting([parent])
        } else {
            NSWorkspace.shared.open(parent)
        }
    }

    private func clearStaleExtensionCookieWarningIfNeeded() {
        guard cookieMode == "browser_auto" else { return }
        guard let warning = vm.cookieWarning else { return }
        if warning.localizedCaseInsensitiveContains("chrome extension mode is selected")
            || warning.localizedCaseInsensitiveContains("chrome companion mode is selected")
        {
            vm.dismissCookieWarning()
        }
    }

    @discardableResult
    private func openInGoogleChrome(_ rawURL: String) -> Bool {
        guard !rawURL.isEmpty else { return false }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", "Google Chrome", rawURL]
        do {
            try process.run()
            return true
        } catch {
            downloadsListLog.debug("open -a Google Chrome failed: \(error.localizedDescription, privacy: .public)")
        }
        if let fallbackURL = URL(string: rawURL) {
            return NSWorkspace.shared.open(fallbackURL)
        }
        return false
    }

    // MARK: - Key handling

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        claimKeyWindow()
        let vm = vm
        keyMonitor = NSEventMonitorHandle(local: .keyDown) { event in
            let visibleRows = vm.presentation.visibleRows(for: filter)
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
                var ids: [RecordID] = []
                ids.reserveCapacity(vm.selectedIDs.count)
                for row in visibleRows where vm.selectedIDs.contains(row.id.rawValue) {
                    ids.append(row.id)
                }
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
            visibleRows: visibleRowsForCurrentFilter(),
            selectedIDs: &vm.selectedIDs,
            anchorID: &vm.anchorID,
            modifiers: flags
        )
    }
}

private struct DownloadsSurfaceDivider: View {
    var body: some View {
        Rectangle()
            .fill(MAYNTheme.divider)
            .frame(maxWidth: .infinity)
            .frame(height: 1)
    }
}

private struct DownloadsListSurfaceFrame: ViewModifier {
    let surface: DownloadsListSurface

    func body(content: Content) -> some View {
        if surface == .commandCenter {
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            content.frame(maxWidth: .infinity)
        }
    }
}
