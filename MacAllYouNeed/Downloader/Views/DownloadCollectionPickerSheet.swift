import AppKit
import Core
import SwiftUI

struct DownloadCollectionPickerSheet: View {
    let sourceURL: String
    let vm: DownloaderViewModel
    let onClose: () -> Void

    @State private var list: PlaylistListResult?
    @State private var loading = true
    @State private var busy = false
    @State private var error = ""
    @State private var selected = Set<String>()

    private var items: [PlaylistEntryRow] { list?.items ?? [] }

    private var headerTitle: String {
        if let name = list?.collectionTitle.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return "\(name) — pick videos"
        }
        return "\(DownloadURLClassifier.collectionPickerLabel(for: sourceURL)) — pick videos"
    }

    private var countSummary: String? {
        guard !loading, !items.isEmpty else { return nil }
        let n = items.count
        return "\(n) video\(n == 1 ? "" : "s") loaded — end of list"
    }

    var body: some View {
        DownloadPickerSheetChrome(
            title: headerTitle,
            sourceURL: sourceURL,
            onClose: onClose,
            toolbar: { toolbar },
            content: { bodyContent },
            footer: { footer }
        )
        .task { await loadList() }
    }

    @ViewBuilder
    private var toolbar: some View {
        HStack(spacing: 8) {
            DownloadPickerToolbarButton(
                title: selected.count == items.count && !items.isEmpty ? "Deselect all" : "Select all",
                symbol: selected.count == items.count && !items.isEmpty ? "checkmark.square" : "square"
            ) {
                if selected.count == items.count {
                    selected.removeAll()
                } else {
                    let snapshot = items
                    Task.detached(priority: .userInitiated) { [snapshot] in
                        let ids = Set(snapshot.map { $0.pageURL.isEmpty ? $0.id : $0.pageURL })
                        await MainActor.run {
                            selected = ids
                        }
                    }
                }
            }
            DownloadPickerToolbarButton(title: "Open in browser", symbol: "safari") {
                if let url = URL(string: sourceURL) {
                    NSWorkspace.shared.open(url)
                }
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var bodyContent: some View {
        VStack(spacing: 10) {
            if loading {
                Spacer()
                ProgressView()
                Text("Loading video list…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
            } else if items.isEmpty {
                if !error.isEmpty {
                    DownloadPickerErrorBanner(message: error)
                        .padding(.horizontal, 20)
                }
                Spacer()
                VStack(spacing: 8) {
                    Text("No videos found.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text("If this playlist or channel is restricted, keep Browser Auto enabled and verify your cookie profile in Downloads settings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    MAYNButton("Open Downloads settings") {
                        NotificationCenter.default.post(name: .mainWindowSettingsRequested, object: "downloads")
                    }
                }
                Spacer()
            } else {
                if !error.isEmpty {
                    DownloadPickerErrorBanner(message: error)
                        .padding(.horizontal, 20)
                }
                if let countSummary {
                    DownloadPickerStatusBanner(text: countSummary)
                        .padding(.horizontal, 20)
                }
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(items) { row in
                            let key = rowKey(row)
                            DownloadPickerEntryRow(
                                title: row.title,
                                subtitle: entrySubtitle(row),
                                thumbnailURL: items.count > 100 ? nil : (row.thumbnail.isEmpty ? nil : URL(string: row.thumbnail)),
                                trailingID: row.id,
                                isSelected: selected.contains(key),
                                onToggle: { toggle(key) }
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                }
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        HStack {
            Spacer()
            MAYNButton("Cancel", action: onClose)
            MAYNButton("Add \(selected.count) to queue", role: .primary) {
                Task { await handleDownload() }
            }
            .disabled(selected.isEmpty || busy || loading)
            .keyboardShortcut(.return)
        }
    }

    private func rowKey(_ row: PlaylistEntryRow) -> String {
        row.pageURL.isEmpty ? row.id : row.pageURL
    }

    private func toggle(_ key: String) {
        if selected.contains(key) {
            selected.remove(key)
        } else {
            selected.insert(key)
        }
    }

    private func entrySubtitle(_ row: PlaylistEntryRow) -> String {
        [row.channel.isEmpty ? list?.channel : row.channel, DownloadPickerDurationFormatting.format(row.durationSeconds)]
            .compactMap { value in
                let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return trimmed.isEmpty ? nil : trimmed
            }
            .joined(separator: " · ")
    }

    private func loadList() async {
        loading = true
        error = ""
        list = nil
        selected.removeAll()
        do {
            list = try await vm.coordinator.listCollectionEntries(url: sourceURL)
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }

    private func handleDownload() async {
        guard let list, !selected.isEmpty else { return }
        busy = true
        error = ""
        let selectionCount = selected.count
        let snapshotItems = list.items
        let snapshotSelected = selected
        let selection = await Task.detached(priority: .userInitiated) { [snapshotItems, snapshotSelected, sourceURL, channel = list.channel] in
            let rows = snapshotItems.filter { snapshotSelected.contains($0.pageURL.isEmpty ? $0.id : $0.pageURL) }
            let entries = rows.map { row in
                BulkEnqueueEntry(
                    pageURL: row.pageURL.isEmpty ? sourceURL : row.pageURL,
                    title: String(row.title.prefix(200)),
                    channel: row.channel.isEmpty ? channel : row.channel,
                    thumbnailURL: row.thumbnail.nilIfEmpty,
                    durationSeconds: row.durationSeconds > 0 ? row.durationSeconds : nil,
                    playlistIndex: row.playlistIndex
                )
            }
            let title = channel.nilIfEmpty ?? "Downloads"
            return (title, entries)
        }.value
        let quality = AppGroupSettings.defaults.integer(forKey: "downloadDefaultVideoQuality")
        let preset = DownloadFormatPreset.fromDefaultQualitySetting(quality == 0 ? 1080 : quality)
        Task.detached(priority: .userInitiated) { [selection, preset, vm] in
            do {
                try await vm.enqueueBulk(
                    entries: selection.1,
                    collectionTitle: selection.0,
                    kind: .playlist,
                    formatArgs: preset.ytdlpArgs()
                )
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.busy = false
                }
            }
        }
        await MainActor.run {
            onClose()
            busy = false
            CopyHUD.show(selectionCount == 1 ? "Added to Downloads" : "Added \(selectionCount) to queue", symbol: "arrow.down.circle.fill")
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
