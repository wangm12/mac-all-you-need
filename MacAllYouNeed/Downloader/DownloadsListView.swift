import AppKit
import Core
import Platform
import SwiftUI

enum DownloadStatePresentation {
    static func badgeText(for state: DownloadState, isMerging: Bool) -> String {
        switch state {
        case .running: isMerging ? "Merging" : "Downloading"
        case .paused: "Paused"
        case .queued: "Queued"
        case .completed: "Done"
        case .failed: "Failed"
        }
    }

    static func pillKind(for state: DownloadState) -> StatusPill.Kind {
        switch state {
        case .completed: .success
        case .failed: .danger
        case .paused: .warning
        case .running: .progress
        case .queued: .neutral
        }
    }
}

enum DownloadJobRowActionPresentation {
    static func primaryActionTitle(for state: DownloadState) -> String {
        switch state {
        case .running: "Pause"
        case .paused: "Resume"
        case .queued: "Cancel"
        case .completed: "Open Folder"
        case .failed: "Retry"
        }
    }

    static func primaryActionSymbol(for state: DownloadState) -> String {
        switch state {
        case .running: "pause.fill"
        case .paused: "play.fill"
        case .queued: "xmark"
        case .completed: "folder"
        case .failed: "arrow.counterclockwise"
        }
    }

    static func isRetryable(_ state: DownloadState) -> Bool {
        state == .failed
    }
}

struct DownloadFolderOpenTarget: Equatable {
    let folderURL: URL

    static func completedRecord(_ record: DownloadRecord) -> DownloadFolderOpenTarget {
        DownloadFolderOpenTarget(
            folderURL: URL(fileURLWithPath: record.destinationPath).deletingLastPathComponent()
        )
    }

    static func defaultDownloadFolder(downloadDir: String) -> DownloadFolderOpenTarget {
        DownloadFolderOpenTarget(
            folderURL: URL(
                fileURLWithPath: DownloadDestinationPresentation.effectivePath(downloadDir: downloadDir),
                isDirectory: true
            )
        )
    }
}

enum DownloadJobRowHoverPresentation {
    static let missingErrorHelpText = "No captured yt-dlp error is available for this failed download. Retry the row to capture fresh stderr details."

    static func rowHelpText(for model: DownloadJobRowModel) -> String? {
        guard model.state == .failed else { return nil }
        let trimmed = model.errorTooltip?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? missingErrorHelpText : trimmed
    }

    static func inlineErrorLineLimit(isHovering: Bool) -> Int? {
        isHovering ? nil : 1
    }
}

enum DownloadsListFilter {
    case all
    case activeQueue
    case completed

    func includes(_ state: DownloadState) -> Bool {
        switch self {
        case .all:
            true
        case .activeQueue:
            switch state {
            case .queued, .running, .paused, .failed:
                true
            case .completed:
                false
            }
        case .completed:
            state == .completed
        }
    }
}

struct DownloadsEmptyStateModel: Equatable {
    let title: String
    let subtitle: String
    let secondaryActionTitle: String?
    let primaryActionTitle: String?
}

enum DownloadsEmptyStatePresentation {
    static func model(for filter: DownloadsListFilter) -> DownloadsEmptyStateModel {
        switch filter {
        case .all, .activeQueue:
            DownloadsEmptyStateModel(
                title: "No downloads queued",
                subtitle: "Add a URL, paste with ⌘V, or send a link from the browser extension.",
                secondaryActionTitle: "Paste URL",
                primaryActionTitle: "Add URL"
            )
        case .completed:
            DownloadsEmptyStateModel(
                title: "No completed downloads",
                subtitle: "Finished media will appear here with quick access to its folder.",
                secondaryActionTitle: nil,
                primaryActionTitle: nil
            )
        }
    }
}

enum DownloadsQueuePresentation {
    static func visibleRows(_ rows: [DownloadRecord], filter: DownloadsListFilter) -> [DownloadRecord] {
        rows.filter { filter.includes($0.state) }
    }

    static func showsFailedBanner(rows: [DownloadRecord], filter: DownloadsListFilter) -> Bool {
        guard filter != .completed else { return false }
        return visibleRows(rows, filter: filter).contains { $0.state == .failed }
    }

    static func headerActionTitle(rows: [DownloadRecord], filter: DownloadsListFilter) -> String? {
        switch filter {
        case .activeQueue, .all:
            showsFailedBanner(rows: rows, filter: filter) ? "Retry Failed" : nil
        case .completed:
            visibleRows(rows, filter: filter).isEmpty ? nil : "Open Folder"
        }
    }
}

struct DownloadJobRowModel: Identifiable {
    let id: RecordID
    let sourceURL: String
    let title: String
    let subtitle: String
    let thumbnailURL: URL?
    let state: DownloadState
    let statusText: String
    let phase: String
    let progress: Double
    let speedText: String?
    let etaText: String?
    let inlineError: String?
    let errorTooltip: String?
    let destinationPath: String?

    var statusPillKind: StatusPill.Kind {
        DownloadStatePresentation.pillKind(for: state)
    }

    init(record: DownloadRecord, progress: DownloadProgress?, statusText: String?) {
        id = record.id
        sourceURL = record.url
        title = record.videoTitle ?? record.title
        subtitle = Self.subtitle(for: record)
        thumbnailURL = record.thumbnailURL.flatMap(URL.init(string:))
        state = record.state
        let isMerging = Self.isMerging(statusText)
        self.statusText = DownloadStatePresentation.badgeText(for: record.state, isMerging: isMerging)
        phase = Self.phase(for: record, statusText: statusText, isMerging: isMerging)
        self.progress = Self.progressFraction(for: record, progress: progress)
        speedText = Self.speedText(for: progress)
        etaText = Self.etaText(for: progress, state: record.state)
        inlineError = Self.inlineError(for: record)
        errorTooltip = Self.inlineError(for: record)
        destinationPath = record.destinationPath
    }

    private static func isMerging(_ statusText: String?) -> Bool {
        let phase = statusText?.lowercased() ?? ""
        return phase.contains("merg") || phase.contains("remux")
    }

    private static func subtitle(for record: DownloadRecord) -> String {
        let parts: [String] = [record.channelName, record.durationSeconds.map(formatDuration)]
            .compactMap { $0 }
        guard !parts.isEmpty else { return record.url }
        return parts.joined(separator: " · ")
    }

    private static func phase(for record: DownloadRecord, statusText: String?, isMerging _: Bool) -> String {
        switch record.state {
        case .running:
            let trimmed = statusText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? "Downloading" : trimmed
        case .paused:
            return "Paused; resume continues from partial file"
        case .queued:
            return "Waiting for an available slot"
        case .completed:
            return "Completed"
        case .failed:
            return "Failed during extractor step"
        }
    }

    private static func progressFraction(for record: DownloadRecord, progress: DownloadProgress?) -> Double {
        if record.state == .completed { return 1 }
        if let progress {
            if let downloaded = progress.downloadedBytes, let total = progress.totalBytes, total > 0 {
                return clamped(Double(downloaded) / Double(total))
            }
            return clamped(progress.fraction)
        }
        if let total = record.bytesTotal, total > 0 {
            return clamped(Double(record.bytesDownloaded) / Double(total))
        }
        return 0
    }

    private static func speedText(for progress: DownloadProgress?) -> String? {
        guard let speed = progress?.speedBytesPerSec, speed > 0 else { return nil }
        return "\(ByteCountFormatter.string(fromByteCount: Int64(speed), countStyle: .file))/s"
    }

    private static func etaText(for progress: DownloadProgress?, state: DownloadState) -> String? {
        guard state == .running, let eta = progress?.etaSeconds, eta > 0 else { return nil }
        return String(format: "ETA %d:%02d", eta / 60, eta % 60)
    }

    private static func inlineError(for record: DownloadRecord) -> String? {
        guard record.state == .failed else { return nil }
        let trimmed = record.lastError?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func formatDuration(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let remainingSeconds = seconds % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
            : String(format: "%d:%02d", minutes, remainingSeconds)
    }

    private static func clamped(_ value: Double) -> Double {
        min(1, max(0, value))
    }
}

enum DownloadsListSurface {
    case main
    case commandCenter
}

struct DownloadAddURLSheet: View {
    @Binding var urlString: String
    let onCancel: () -> Void
    let onDownload: (String) -> Void

    private var trimmedURL: String {
        urlString.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Add download URL")
                    .font(.title3.weight(.semibold))
                Text("Paste a video or audio URL. Metadata is fetched before the download starts.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            MAYNTextField(
                placeholder: "https://www.youtube.com/watch?v=...",
                text: $urlString,
                width: MAYNControlMetrics.wideTextFieldWidth,
                autofocus: true
            )

            HStack(spacing: 8) {
                StatusPill(text: "Ready", kind: .neutral)
                Text("Metadata will appear immediately after enqueue.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                MAYNButton("Cancel", action: onCancel)
                MAYNButton("Download", role: .primary) {
                    onDownload(trimmedURL)
                }
                .disabled(trimmedURL.isEmpty)
                .keyboardShortcut(.return)
            }
        }
        .padding(24)
        .frame(width: 430)
        .background(MAYNTheme.window)
    }
}

struct DownloadsListView: View {
    @Bindable var vm: DownloaderViewModel
    var filter: DownloadsListFilter = .all
    var surface: DownloadsListSurface = .main
    var onPasteURL: (() -> Void)?
    var onAddURL: (() -> Void)?
    @FocusState private var listFocused: Bool
    @State private var keyMonitor: NSEventMonitorHandle? = nil

    var body: some View {
        VStack(spacing: 0) {
            if surface == .main {
                listHeader
                MAYNDivider()
                if let warning = vm.cookieWarning {
                    cookieWarningBanner(warning)
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
                        ForEach(visibleRows, id: \.id) { record in
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
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(surface == .main ? Color.clear : MAYNTheme.window)
        .focusable()
        .focusEffectDisabled()
        .focused($listFocused)
        .onAppear {
            listFocused = true
            installKeyMonitor()
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
                vm.selectedIDs = Set(visibleRows.map(\.id.rawValue))
                vm.anchorID = visibleRows.first?.id.rawValue
                return nil
            }
            if isCommand, character == "v" {
                pasteURL()
                return nil
            }
            if event.keyCode == 53, !vm.selectedIDs.isEmpty {
                vm.selectedIDs = []
                vm.anchorID = nil
                return nil
            }
            return event
        }
    }

    private func claimKeyWindow() {
        guard surface == .commandCenter else { return }
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            for window in NSApp.windows {
                let name = String(describing: type(of: window))
                if name.contains("MenuBarExtra") || name.contains("NSStatusBarWindow") {
                    window.makeKeyAndOrderFront(nil)
                    return
                }
            }
        }
    }

    // MARK: - Selection

    private func handleTap(id: String) {
        listFocused = true
        claimKeyWindow()
        let flags = NSApp.currentEvent?.modifierFlags ?? []
        let isCommand = flags.contains(.command)
        let isShift = flags.contains(.shift)

        if isCommand {
            if vm.selectedIDs.contains(id) {
                vm.selectedIDs.remove(id)
            } else {
                vm.selectedIDs.insert(id)
                vm.anchorID = id
            }
        } else if isShift, let anchor = vm.anchorID {
            let ids = visibleRows.map(\.id.rawValue)
            if let start = ids.firstIndex(of: anchor),
               let end = ids.firstIndex(of: id)
            {
                let lowerBound = min(start, end)
                let upperBound = max(start, end)
                vm.selectedIDs = Set(ids[lowerBound ... upperBound])
            }
        } else {
            if vm.selectedIDs == [id] {
                vm.selectedIDs = []
                vm.anchorID = nil
            } else {
                vm.selectedIDs = [id]
                vm.anchorID = id
            }
        }
    }
}

private struct DownloadsEmptyStateView: View {
    let model: DownloadsEmptyStateModel
    let onPasteURL: () -> Void
    let onAddURL: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(.secondary)
            VStack(spacing: 4) {
                Text(model.title)
                    .font(.callout.weight(.semibold))
                Text(model.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if model.secondaryActionTitle != nil || model.primaryActionTitle != nil {
                HStack(spacing: 8) {
                    if let secondaryTitle = model.secondaryActionTitle {
                        MAYNButton(secondaryTitle, action: onPasteURL)
                    }
                    if let primaryTitle = model.primaryActionTitle {
                        MAYNButton(primaryTitle, role: .primary, action: onAddURL)
                    }
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct DownloadJobRow: View {
    let model: DownloadJobRowModel
    let isSelected: Bool
    var isCompact = false
    let onTap: () -> Void
    let onPrimaryAction: () -> Void
    let onDelete: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    private var thumbnailSize: CGSize {
        isCompact ? CGSize(width: 56, height: 34) : CGSize(width: 82, height: 48)
    }

    var body: some View {
        HStack(alignment: .center, spacing: isCompact ? 9 : 14) {
            thumbnailView

            VStack(alignment: .leading, spacing: isCompact ? 4 : 6) {
                titleLine
                if !model.subtitle.isEmpty {
                    Text(model.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                progressBar
                captionView
            }
        }
        .padding(.horizontal, MAYNControlMetrics.rowHorizontalPadding)
        .padding(.vertical, isCompact ? 8 : 12)
        .background(rowBackground)
        .overlay(MAYNDivider(), alignment: .bottom)
        .overlay(
            RoundedRectangle(cornerRadius: MAYNControlMetrics.controlRadius, style: .continuous)
                .stroke(isSelected ? MAYNTheme.focusRing : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .downloadRowHelp(DownloadJobRowHoverPresentation.rowHelpText(for: model))
        .onTapGesture { onTap() }
        .onHover { isHovering = $0 }
        .animation(MAYNMotion.hoverAnimation(reduceMotion: reduceMotion), value: isHovering)
        .animation(MAYNMotion.controlAnimation(reduceMotion: reduceMotion), value: model.progress)
    }

    private var titleLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            StatusPill(text: model.statusText.uppercased(), kind: model.statusPillKind)
            Text(model.title)
                .font(isCompact ? .caption.weight(.semibold) : .callout.weight(.semibold))
                .lineLimit(1)
            Spacer(minLength: 6)
            if !isCompact {
                actionButtons
            }
        }
    }

    private var thumbnailView: some View {
        Group {
            if let thumbnailURL = model.thumbnailURL {
                AsyncImage(url: thumbnailURL) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    thumbnailPlaceholder(symbol: "photo")
                }
            } else if URLDetector.videoBearingURL(in: model.sourceURL) == nil {
                thumbnailPlaceholder(symbol: "link.circle")
            } else {
                thumbnailPlaceholder(symbol: "play.rectangle")
            }
        }
        .frame(width: thumbnailSize.width, height: thumbnailSize.height)
        .clipShape(RoundedRectangle(cornerRadius: MAYNControlMetrics.controlRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MAYNControlMetrics.controlRadius, style: .continuous)
                .stroke(MAYNTheme.subtleBorder, lineWidth: 1)
        )
    }

    private func thumbnailPlaceholder(symbol: String) -> some View {
        ZStack {
            MAYNTheme.elevated
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    private var progressBar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(MAYNTheme.divider)
                Capsule()
                    .fill(progressColor)
                    .frame(width: max(2, geometry.size.width * model.progress))
            }
        }
        .frame(height: isCompact ? 2 : 3)
    }

    private var captionView: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Text(model.phase)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .downloadRowHelp(DownloadJobRowHoverPresentation.rowHelpText(for: model))
                if let speedText = model.speedText {
                    Text("· \(speedText)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if let etaText = model.etaText, !isCompact {
                    Text(etaText)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            if let inlineError = model.inlineError {
                Text(inlineError)
                    .font(.caption)
                    .foregroundStyle(MAYNTheme.danger)
                    .lineLimit(DownloadJobRowHoverPresentation.inlineErrorLineLimit(isHovering: isHovering))
                    .truncationMode(.tail)
                    .help(DownloadJobRowHoverPresentation.rowHelpText(for: model) ?? inlineError)
            }
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 6) {
            DownloadIconButton(
                symbolName: DownloadJobRowActionPresentation.primaryActionSymbol(for: model.state),
                role: model.state == .failed ? .destructive : .secondary,
                accessibilityLabel: DownloadJobRowActionPresentation.primaryActionTitle(for: model.state),
                action: onPrimaryAction
            )
            DownloadIconButton(
                symbolName: "trash",
                role: .destructive,
                accessibilityLabel: "Delete",
                action: onDelete
            )
        }
    }

    private var rowBackground: Color {
        if isSelected { return MAYNTheme.selected }
        if isHovering { return MAYNTheme.hover }
        return Color.clear
    }

    private var progressColor: Color {
        switch model.state {
        case .completed: MAYNTheme.success
        case .failed: MAYNTheme.danger
        case .paused: MAYNTheme.warning
        case .running: MAYNTheme.progress
        case .queued: .secondary
        }
    }
}

private struct DownloadRowHelpModifier: ViewModifier {
    let helpText: String?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let helpText {
            content.help(helpText)
        } else {
            content
        }
    }
}

private extension View {
    func downloadRowHelp(_ helpText: String?) -> some View {
        modifier(DownloadRowHelpModifier(helpText: helpText))
    }
}

private struct DownloadIconButton: View {
    enum Role {
        case secondary
        case destructive
    }

    let symbolName: String
    var role: Role = .secondary
    let accessibilityLabel: String
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false
    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbolName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(foreground)
                .frame(width: MAYNControlMetrics.controlHeight, height: MAYNControlMetrics.controlHeight)
                .background(background, in: RoundedRectangle(cornerRadius: MAYNControlMetrics.controlRadius, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: MAYNControlMetrics.controlRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .scaleEffect(isPressed && !reduceMotion ? 0.985 : 1)
        .onHover { isHovering = $0 }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .animation(MAYNMotion.hoverAnimation(reduceMotion: reduceMotion), value: isHovering)
        .animation(MAYNMotion.fastAnimation(reduceMotion: reduceMotion), value: isPressed)
    }

    private var foreground: Color {
        role == .destructive ? MAYNTheme.danger : .secondary
    }

    private var background: Color {
        if isPressed { return MAYNTheme.elevatedPressed }
        if isHovering { return MAYNTheme.elevatedHover }
        return Color.clear
    }
}
