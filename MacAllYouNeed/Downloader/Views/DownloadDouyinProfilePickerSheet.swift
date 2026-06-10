import AppKit
import Core
import SwiftUI
import WebKit

@MainActor
final class DouyinProfileBrowserRecovery: NSObject, WKNavigationDelegate {
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<[DouyinProfilePostRow], Error>?
    private var pollingTask: Task<Void, Never>?

    func load(profileURL: String) async throws -> [DouyinProfilePostRow] {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let config = WKWebViewConfiguration()
            let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 960, height: 720), configuration: config)
            view.navigationDelegate = self
            webView = view
            guard let url = URL(string: profileURL) else {
                continuation.resume(throwing: PlaylistListError.noEntries)
                return
            }
            view.load(URLRequest(url: url))
            startPolling(profileURL: profileURL, webView: view, timeoutSeconds: 45)
        }
    }

    private func finish(with rows: [DouyinProfilePostRow]) {
        guard let continuation else { return }
        self.continuation = nil
        pollingTask?.cancel()
        pollingTask = nil
        webView = nil
        if rows.isEmpty {
            continuation.resume(throwing: PlaylistListError.noEntries)
        } else {
            continuation.resume(returning: rows)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Do not finish immediately. Douyin profile pages populate posts asynchronously.
        // Polling task started in `load` will keep scrolling + re-evaluating.
    }

    private func startPolling(profileURL: String, webView: WKWebView, timeoutSeconds: Int) {
        pollingTask?.cancel()
        pollingTask = Task { @MainActor in
            let started = Date()
            while continuation != nil, Date().timeIntervalSince(started) < Double(timeoutSeconds) {
                let html = await viewHTML(webView)
                let rows = DouyinProfileLister.parsePosts(from: html, profileURL: profileURL)
                if !rows.isEmpty {
                    finish(with: rows)
                    return
                }
                _ = try? await webView.callAsyncJavaScript(
                    "window.scrollTo(0, document.body.scrollHeight); return true;",
                    arguments: [:],
                    in: nil,
                    contentWorld: .page
                )
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }
            if continuation != nil {
                let html = await viewHTML(webView)
                finish(with: DouyinProfileLister.parsePosts(from: html, profileURL: profileURL))
            }
        }
    }

    private func viewHTML(_ webView: WKWebView) async -> String {
        await withCheckedContinuation { continuation in
            webView.evaluateJavaScript("document.documentElement.outerHTML.toString()") { result, _ in
                continuation.resume(returning: result as? String ?? "")
            }
        }
    }
}

struct DownloadDouyinProfilePickerSheet: View {
    let profileURL: String
    let vm: DownloaderViewModel
    let onClose: () -> Void

    @State private var items: [DouyinProfilePostRow] = []
    @State private var loading = true
    @State private var busy = false
    @State private var browserBusy = false
    @State private var pageBusy = false
    @State private var loadAllBusy = false
    @State private var error = ""
    @State private var listWarning = ""
    @State private var nextCursor: String?
    @State private var hasMore = false
    @State private var loadAllNote = ""
    @State private var enrichingIDs = Set<String>()
    @State private var selected = Set<String>()
    @State private var normalizationNotice = ""

    private var headerTitle: String {
        let author = items.first?.author.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !author.isEmpty { return "\(author) — pick posts" }
        return "Douyin profile — pick posts"
    }

    private var countSummary: String? {
        guard !loading, !items.isEmpty else { return nil }
        let base = "\(items.count) post\(items.count == 1 ? "" : "s") loaded"
        if hasMore, nextCursor != nil { return "\(base) — more available (Load more)" }
        return "\(base) — end of list"
    }

    var body: some View {
        DownloadPickerSheetChrome(
            title: headerTitle,
            sourceURL: profileURL,
            onClose: onClose,
            toolbar: { toolbar },
            content: { bodyContent },
            footer: { footer }
        )
        .task { await loadInitial() }
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
                    selected = Set(items.map(\.awemeId))
                }
            }
            DownloadPickerToolbarButton(title: "Load in browser", symbol: "globe") {
                Task { await loadInBrowser() }
            }
            DownloadPickerToolbarButton(title: "Load more", symbol: "arrow.down.circle") {
                Task { await loadMore() }
            }
            .disabled(loading || busy || browserBusy || pageBusy || loadAllBusy || items.isEmpty)
            DownloadPickerToolbarButton(title: "Load all", symbol: "arrow.down.to.line") {
                Task { await loadAll() }
            }
            .disabled(loading || busy || browserBusy || pageBusy || loadAllBusy || items.isEmpty)
            DownloadPickerToolbarButton(title: "Open in browser", symbol: "safari") {
                if let url = URL(string: profileURL) { NSWorkspace.shared.open(url) }
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
                Text("Loading posts…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
            } else if items.isEmpty {
                if !error.isEmpty {
                    DownloadPickerErrorBanner(message: error).padding(.horizontal, 20)
                }
                Spacer()
                Text("No videos found.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                if !error.isEmpty {
                    DownloadPickerErrorBanner(message: error).padding(.horizontal, 20)
                }
                if !normalizationNotice.isEmpty {
                    DownloadPickerStatusBanner(text: normalizationNotice).padding(.horizontal, 20)
                }
                if !listWarning.isEmpty {
                    DownloadPickerStatusBanner(text: listWarning).padding(.horizontal, 20)
                }
                if let countSummary {
                    DownloadPickerStatusBanner(text: countSummary).padding(.horizontal, 20)
                }
                if loadAllBusy || !loadAllNote.isEmpty {
                    DownloadPickerStatusBanner(text: loadAllBusy ? "Loading all pages…" : loadAllNote).padding(.horizontal, 20)
                }
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(items) { row in
                            DownloadPickerEntryRow(
                                title: row.title,
                                subtitle: row.author,
                                thumbnailURL: row.thumbnail.isEmpty ? nil : URL(string: row.thumbnail),
                                trailingID: row.awemeId,
                                isSelected: selected.contains(row.awemeId),
                                onToggle: { toggle(row.awemeId) }
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
            .disabled(selected.isEmpty || busy || loading || browserBusy || pageBusy || loadAllBusy)
        }
    }

    private func toggle(_ id: String) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    private func loadInitial() async {
        loading = true
        error = ""
        listWarning = ""
        normalizationNotice = ""
        nextCursor = nil
        hasMore = false
        loadAllNote = ""
        items = []
        selected.removeAll()
        do {
            guard let ytdlp = try? vm.coordinator.binaries.ytdlpPath() else {
                throw PlaylistListError.ytdlpFailed(code: -1, message: "yt-dlp not available")
            }
            if let secUid = DouyinProfileLister.extractSecUid(from: profileURL) {
                let canonical = "https://www.douyin.com/user/\(secUid)"
                if canonical != profileURL {
                    normalizationNotice = "Normalized profile URL for listing: \(canonical)"
                }
            }
            let cookieFile = cookieFileURL()
            let result = try await DouyinProfileLister.listFirstPage(
                profileURL: profileURL,
                ytdlp: ytdlp,
                cookieFile: cookieFile
            )
            items = result.items
            nextCursor = result.cursor
            hasMore = result.hasMore
            listWarning = result.warnings.joined(separator: " ")
            await enrichMissingMetadata(limit: 12)
        } catch {
            if case PlaylistListError.noEntries = error {
                listWarning = "No list returned from direct fetch. Trying browser-session recovery…"
                await loadInBrowser()
            } else {
                self.error = error.localizedDescription
            }
        }
        loading = false
    }

    private func loadInBrowser() async {
        browserBusy = true
        listWarning = "Opening browser with your session — this may take up to a minute."
        do {
            let recovery = DouyinProfileBrowserRecovery()
            let rows = try await recovery.load(profileURL: profileURL)
            var seen = Set(items.map(\.awemeId))
            for row in rows where seen.insert(row.awemeId).inserted {
                items.append(row)
            }
            listWarning = ""
            await enrichMissingMetadata(limit: 16)
        } catch {
            self.error = error.localizedDescription
        }
        browserBusy = false
    }

    private func loadMore() async {
        guard !pageBusy, !loadAllBusy, !browserBusy else { return }
        if !(hasMore && nextCursor != nil) {
            listWarning = "No API cursor available. Trying browser-session recovery for more posts…"
            await loadInBrowser()
            return
        }
        guard let cursor = nextCursor else { return }
        pageBusy = true
        error = ""
        listWarning = ""
        defer { pageBusy = false }
        do {
            let result = try await DouyinProfileLister.listNextPage(
                profileURL: profileURL,
                cursor: cursor,
                cookieFile: cookieFileURL()
            )
            var seen = Set(items.map(\.awemeId))
            for row in result.items where seen.insert(row.awemeId).inserted {
                items.append(row)
            }
            nextCursor = result.cursor
            hasMore = result.hasMore
            if !result.warnings.isEmpty {
                listWarning = result.warnings.joined(separator: " ")
            }
            await enrichMissingMetadata(limit: 16)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func loadAll() async {
        guard !loadAllBusy, !pageBusy, !browserBusy else { return }
        loadAllBusy = true
        loadAllNote = ""
        error = ""
        listWarning = ""
        defer { loadAllBusy = false }

        if !(hasMore && nextCursor != nil) {
            var rounds = 0
            var previousCount = items.count
            while rounds < 6, items.count < DouyinProfileListResult.maxLoadAllItems {
                rounds += 1
                loadAllNote = "Loading from browser round \(rounds)…"
                await loadInBrowser()
                await enrichMissingMetadata(limit: 20)
                if items.count == previousCount { break }
                previousCount = items.count
            }
            loadAllNote = "Browser-assisted load complete."
            return
        }

        var pages = 0
        while hasMore,
              let cursor = nextCursor,
              pages < DouyinProfileListResult.maxLoadAllPages,
              items.count < DouyinProfileListResult.maxLoadAllItems
        {
            pages += 1
            loadAllNote = "Loading page \(pages)…"
            do {
                let result = try await DouyinProfileLister.listNextPage(
                    profileURL: profileURL,
                    cursor: cursor,
                    cookieFile: cookieFileURL()
                )
                var seen = Set(items.map(\.awemeId))
                for row in result.items where seen.insert(row.awemeId).inserted {
                    items.append(row)
                }
                nextCursor = result.cursor
                hasMore = result.hasMore
                if !result.warnings.isEmpty {
                    listWarning = result.warnings.joined(separator: " ")
                }
                await enrichMissingMetadata(limit: 20)
            } catch {
                self.error = error.localizedDescription
                break
            }
            try? await Task.sleep(nanoseconds: 400_000_000)
        }

        if items.count >= DouyinProfileListResult.maxLoadAllItems {
            loadAllNote = "Stopped at \(DouyinProfileListResult.maxLoadAllItems) items (safety cap)."
        } else if hasMore, pages >= DouyinProfileListResult.maxLoadAllPages {
            loadAllNote = "Stopped at \(DouyinProfileListResult.maxLoadAllPages) pages (safety cap)."
        } else {
            loadAllNote = "List complete."
        }
    }

    private func enrichMissingMetadata(limit: Int) async {
        guard let ytdlp = try? vm.coordinator.binaries.ytdlpPath() else { return }
        let cookieFile = cookieFileURL()
        let targetIndexes = items.indices.filter { index in
            let row = items[index]
            let missingThumbnail = row.thumbnail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let genericTitle = row.title.hasPrefix("Douyin post ")
            return (missingThumbnail || genericTitle) && !enrichingIDs.contains(row.awemeId)
        }
        .prefix(limit)

        for index in targetIndexes {
            let row = items[index]
            enrichingIDs.insert(row.awemeId)
            defer { enrichingIDs.remove(row.awemeId) }
            guard let meta = await MetadataFetcher.fetch(url: row.pageURL, ytdlp: ytdlp, cookieFile: cookieFile) else { continue }
            let current = items[index]
            let nextTitle = current.title.hasPrefix("Douyin post ") ? meta.title : current.title
            let nextAuthor = current.author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? meta.channelName : current.author
            let nextThumb = current.thumbnail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? meta.thumbnailURL : current.thumbnail
            items[index] = DouyinProfilePostRow(
                awemeId: current.awemeId,
                title: nextTitle,
                author: nextAuthor,
                thumbnail: nextThumb,
                pageURL: current.pageURL
            )
        }
    }

    private func handleDownload() async {
        guard !selected.isEmpty else { return }
        busy = true
        let rows = items.filter { selected.contains($0.awemeId) }
        let title = rows.first?.author.nilIfEmpty ?? "Douyin profile"
        let entries = rows.enumerated().map { index, row in
            BulkEnqueueEntry(
                pageURL: row.pageURL,
                title: String(row.title.prefix(200)),
                channel: row.author,
                thumbnailURL: row.thumbnail.nilIfEmpty,
                playlistIndex: index + 1
            )
        }
        let quality = AppGroupSettings.defaults.integer(forKey: "downloadDefaultVideoQuality")
        let preset = DownloadFormatPreset.fromDefaultQualitySetting(quality == 0 ? 1080 : quality)
        do {
            try await vm.enqueueBulk(
                entries: entries,
                collectionTitle: title,
                kind: .douyinProfile,
                formatArgs: preset.ytdlpArgs()
            )
            onClose()
        } catch {
            self.error = error.localizedDescription
        }
        busy = false
    }

    private func cookieFileURL() -> URL? {
        let cookieFile = AppGroup.containerURL()
            .appendingPathComponent("cookies/downloader-cookies.txt")
        return FileManager.default.fileExists(atPath: cookieFile.path) ? cookieFile : nil
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
