import AppKit
import Core
import SwiftUI
import WebKit

@MainActor
final class DouyinProfileBrowserRecovery: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<[DouyinProfilePostRow], Error>?
    private var pollingTask: Task<Void, Never>?

    // API interception state — accumulated across all intercepted responses
    private var capturedRows: [DouyinProfilePostRow] = []
    private var capturedIds: Set<String> = []
    private var apiHasMore = true

    // Intercepts fetch() and XHR calls to /aweme/v1/web/aweme/post/ and posts
    // each raw JSON response body back to Swift via the "douyinApiCapture" handler.
    private static let apiInterceptScript = """
    (function() {
      const TARGET = '/aweme/v1/web/aweme/post/';
      const handler = window.webkit?.messageHandlers?.douyinApiCapture;
      if (!handler) return;

      const origFetch = window.fetch;
      window.fetch = async function(...args) {
        const res = await origFetch.apply(this, args);
        try {
          const url = typeof args[0] === 'string' ? args[0] : (args[0]?.url ?? '');
          if (url.includes(TARGET)) {
            res.clone().text().then(t => handler.postMessage(t)).catch(() => {});
          }
        } catch(_) {}
        return res;
      };

      const origOpen = XMLHttpRequest.prototype.open;
      XMLHttpRequest.prototype.open = function(m, url, ...r) {
        this._dy = url && url.includes(TARGET);
        return origOpen.apply(this, [m, url, ...r]);
      };
      const origSend = XMLHttpRequest.prototype.send;
      XMLHttpRequest.prototype.send = function(...a) {
        if (this._dy) {
          this.addEventListener('load', () => {
            try { handler.postMessage(this.responseText); } catch(_) {}
          });
        }
        return origSend.apply(this, a);
      };
    })();
    """

    func load(profileURL: String, cookieFile: URL?) async throws -> [DouyinProfilePostRow] {
        capturedRows = []
        capturedIds = []
        apiHasMore = true

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation

            let config = WKWebViewConfiguration()
            config.userContentController.add(self, name: "douyinApiCapture")
            config.userContentController.addUserScript(WKUserScript(
                source: Self.apiInterceptScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            ))

            let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 960, height: 720), configuration: config)
            view.navigationDelegate = self
            webView = view

            guard let url = URL(string: profileURL) else {
                continuation.resume(throwing: PlaylistListError.noEntries)
                return
            }

            // Inject Douyin cookies from our synced cookie file before loading,
            // so the WKWebView authenticates instead of hitting the anti-bot shell.
            let httpCookies = Self.httpCookies(from: cookieFile)
            if httpCookies.isEmpty {
                view.load(URLRequest(url: url))
                startPolling(profileURL: profileURL, webView: view, timeoutSeconds: 60)
            } else {
                let store = view.configuration.websiteDataStore.httpCookieStore
                Task { @MainActor in
                    for cookie in httpCookies {
                        await store.setCookie(cookie)
                    }
                    view.load(URLRequest(url: url))
                    self.startPolling(profileURL: profileURL, webView: view, timeoutSeconds: 60)
                }
            }
        }
    }

    // Parses a Netscape cookie file and returns HTTPCookie objects for Douyin domains.
    private static func httpCookies(from cookieFile: URL?) -> [HTTPCookie] {
        guard let cookieFile,
              let text = try? String(contentsOf: cookieFile, encoding: .utf8)
        else { return [] }

        var cookies: [HTTPCookie] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let raw = String(line)
            guard !raw.hasPrefix("#") else { continue }
            let parts = raw.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard parts.count >= 7 else { continue }
            let domain = parts[0]
            guard domain.contains("douyin") || domain.contains("iesdouyin")
                || domain.contains("bytedance") || domain.contains("toutiao")
                || domain.contains("snssdk") || domain.contains("amemv")
            else { continue }
            let name  = parts[5]
            let value = parts[6].trimmingCharacters(in: .newlines)
            var props: [HTTPCookiePropertyKey: Any] = [
                .domain: domain,
                .path: parts[2].isEmpty ? "/" : parts[2],
                .name: name,
                .value: value,
                .secure: parts[3].uppercased() == "TRUE" ? "TRUE" : "FALSE",
            ]
            if let expiry = Double(parts[4]), expiry > 0 {
                props[.expires] = Date(timeIntervalSince1970: expiry)
            }
            if let cookie = HTTPCookie(properties: props) {
                cookies.append(cookie)
            }
        }
        return cookies
    }

    // Called on main thread by WebKit when JS posts a captured API response.
    nonisolated func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        Task { @MainActor [weak self] in
            guard message.name == "douyinApiCapture" else { return }
            self?.handleCapturedResponse(message.body)
        }
    }

    private func handleCapturedResponse(_ body: Any) {
        guard let text = body as? String,
              let data = text.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }

        let payload = (root["data"] as? [String: Any]) ?? root
        let awemeList = payload["aweme_list"] as? [[String: Any]]
            ?? root["aweme_list"] as? [[String: Any]] ?? []

        let hasMoreRaw = payload["has_more"] ?? root["has_more"]
        let hasMore = (hasMoreRaw as? Bool) == true
            || String(describing: hasMoreRaw ?? "").lowercased() == "true"
            || String(describing: hasMoreRaw ?? "") == "1"
        if !hasMore { apiHasMore = false }

        let profileURL = webView?.url?.absoluteString ?? ""
        for item in awemeList {
            guard let row = DouyinProfileLister.rowFromAwemeItem(item, profileURL: profileURL),
                  capturedIds.insert(row.awemeId).inserted
            else { continue }
            capturedRows.append(row)
        }
    }

    private func finish(with rows: [DouyinProfilePostRow]) {
        guard let continuation else { return }
        self.continuation = nil
        pollingTask?.cancel()
        pollingTask = nil
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "douyinApiCapture")
        webView = nil
        if rows.isEmpty {
            continuation.resume(throwing: PlaylistListError.noEntries)
        } else {
            continuation.resume(returning: rows)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {}

    private func startPolling(profileURL: String, webView: WKWebView, timeoutSeconds: Int) {
        pollingTask?.cancel()
        pollingTask = Task { @MainActor in
            let started = Date()
            var lastCount = 0
            var stagnantRounds = 0

            while continuation != nil, Date().timeIntervalSince(started) < Double(timeoutSeconds) {
                // If the API reported no more pages and count stopped growing, we're done
                if !apiHasMore, !capturedRows.isEmpty {
                    stagnantRounds = capturedRows.count == lastCount ? stagnantRounds + 1 : 0
                    if stagnantRounds >= 2 {
                        finish(with: capturedRows)
                        return
                    }
                } else if capturedRows.count > lastCount {
                    stagnantRounds = 0
                }
                lastCount = capturedRows.count

                if capturedRows.count >= DouyinProfileListResult.maxLoadAllItems {
                    finish(with: capturedRows)
                    return
                }

                _ = try? await webView.callAsyncJavaScript(
                    "window.scrollTo(0, document.body.scrollHeight); return true;",
                    arguments: [:], in: nil, contentWorld: .page
                )
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }

            // Timeout: if API interception got nothing, fall back to HTML parsing
            guard continuation != nil else { return }
            if capturedRows.isEmpty {
                let html = await viewHTML(webView)
                finish(with: DouyinProfileLister.parsePosts(from: html, profileURL: profileURL))
            } else {
                finish(with: capturedRows)
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
    @State private var selected = Set<String>()
    @State private var normalizationNotice = ""
    @State private var seenIDs = Set<String>()
    @State private var metadataEnrichmentTask: Task<Void, Never>?

    private struct DouyinLoadTimeout: Error {}

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
                    let snapshot = items
                    Task.detached(priority: .userInitiated) { [snapshot] in
                        let ids = Set(snapshot.map(\.awemeId))
                        await MainActor.run {
                            selected = ids
                        }
                    }
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
            } else if browserBusy && items.isEmpty {
                Spacer()
                ProgressView()
                Text("Recovering posts from browser session…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("Keep your logged-in browser window open while recovery runs.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Spacer()
            } else if items.isEmpty {
                if !error.isEmpty {
                    DownloadPickerErrorBanner(message: error).padding(.horizontal, 20)
                }
                Spacer()
                VStack(spacing: 8) {
                    Text("No videos found.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text("Use Load in browser to recover posts from your signed-in Douyin session.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Text("Browser Auto cookies are recommended; Mac All You Need Companion sync is optional.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    MAYNButton("Open Downloads settings") {
                        NotificationCenter.default.post(name: .mainWindowSettingsRequested, object: "downloads")
                    }
                }
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
                                thumbnailURL: items.count > 100 ? nil : (row.thumbnail.isEmpty ? nil : URL(string: row.thumbnail)),
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
        seenIDs.removeAll()
        do {
            let ytdlp: URL
            do {
                let resolved = try await withTimeout(seconds: 8) {
                    await resolveYtDlpPath()
                }
                guard let resolved else {
                    throw PlaylistListError.ytdlpFailed(code: -1, message: "yt-dlp not available")
                }
                ytdlp = resolved
            } catch is DouyinLoadTimeout {
                listWarning = "Timed out preparing direct listing. Trying browser-session recovery…"
                await loadInBrowser()
                loading = false
                return
            }
            if let secUid = DouyinProfileLister.extractSecUid(from: profileURL) {
                let canonical = "https://www.douyin.com/user/\(secUid)"
                if canonical != profileURL {
                    normalizationNotice = "Normalized profile URL for listing: \(canonical)"
                }
            }
            let cookieFile = cookieFileURL()
            let listTask = Task.detached(priority: .userInitiated) {
                try await DouyinProfileLister.listFirstPage(
                    profileURL: profileURL,
                    ytdlp: ytdlp,
                    cookieFile: cookieFile
                )
            }
            let result: DouyinProfileListResult
            do {
                result = try await withTimeout(seconds: 25) {
                    try await listTask.value
                }
            } catch {
                listTask.cancel()
                throw error
            }
            items = result.items
            seenIDs = Set(result.items.map(\.awemeId))
            nextCursor = result.cursor
            hasMore = result.hasMore
            listWarning = result.warnings.joined(separator: " ")
            scheduleMetadataEnrichment(limit: 4)
            if !hasMore, items.count < 50 {
                listWarning = "Direct listing returned a small batch. Use Load in browser to recover more posts."
            }
        } catch is DouyinLoadTimeout {
            listWarning = "Loading posts timed out. Try Load in browser for session-based recovery."
        } catch {
            if case PlaylistListError.noEntries = error {
                listWarning = "No list returned from direct fetch. Trying browser-session recovery…"
                loading = false
                await loadInBrowser()
                return
            } else {
                self.error = error.localizedDescription
            }
        }
        loading = false
    }

    private func resolveYtDlpPath() async -> URL? {
        await Task.detached(priority: .userInitiated) { [binaries = vm.coordinator.binaries] in
            try? binaries.ytdlpPath()
        }.value
    }

    private func withTimeout<T>(seconds: Double, operation: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                let delay = UInt64(max(0, seconds) * 1_000_000_000)
                try await Task.sleep(nanoseconds: delay)
                throw DouyinLoadTimeout()
            }
            let first = try await group.next()!
            group.cancelAll()
            return first
        }
    }

    private func loadInBrowser() async {
        browserBusy = true
        listWarning = "Opening browser with your session — this may take up to a minute."
        do {
            let recovery = DouyinProfileBrowserRecovery()
            let rows = try await recovery.load(profileURL: profileURL, cookieFile: cookieFileURL())
            await mergeRows(rows)
            listWarning = ""
            scheduleMetadataEnrichment(limit: 8)
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
            await mergeRows(result.items)
            nextCursor = result.cursor
            hasMore = result.hasMore
            if !result.warnings.isEmpty {
                listWarning = result.warnings.joined(separator: " ")
            }
            scheduleMetadataEnrichment(limit: 8)
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
            loadAllNote = items.isEmpty
                ? "No API cursor available. Use Load in browser to recover more posts."
                : "List complete."
            return
        }

        var pages = 0
        var pendingRows: [DouyinProfilePostRow] = []
        pendingRows.reserveCapacity(64)
        var mergedCount = items.count
        while hasMore,
              let cursor = nextCursor,
              pages < DouyinProfileListResult.maxLoadAllPages,
              mergedCount < DouyinProfileListResult.maxLoadAllItems
        {
            pages += 1
            loadAllNote = "Loading page \(pages)…"
            do {
                let result = try await Task.detached(priority: .utility) { [profileURL, cursor, cookieFileURL] in
                    try await DouyinProfileLister.listNextPage(
                        profileURL: profileURL,
                        cursor: cursor,
                        cookieFile: cookieFileURL()
                    )
                }.value
                pendingRows.append(contentsOf: result.items)
                nextCursor = result.cursor
                hasMore = result.hasMore
                mergedCount += result.items.count
                if !result.warnings.isEmpty {
                    listWarning = result.warnings.joined(separator: " ")
                }
                if pendingRows.count >= 256 {
                    await mergeRows(pendingRows)
                    pendingRows.removeAll(keepingCapacity: true)
                }
            } catch {
                self.error = error.localizedDescription
                break
            }
            if pages.isMultiple(of: 3) {
                try? await Task.sleep(nanoseconds: 400_000_000)
            } else {
                await Task.yield()
            }
        }

        await mergeRows(pendingRows)
        pendingRows.removeAll(keepingCapacity: true)

        if items.count >= DouyinProfileListResult.maxLoadAllItems {
            loadAllNote = "Stopped at \(DouyinProfileListResult.maxLoadAllItems) items (safety cap)."
        } else if hasMore, pages >= DouyinProfileListResult.maxLoadAllPages {
            loadAllNote = "Stopped at \(DouyinProfileListResult.maxLoadAllPages) pages (safety cap)."
        } else {
            loadAllNote = "List complete."
        }
        scheduleMetadataEnrichment(limit: items.count > 100 ? 0 : 4)
    }

    private func mergeRows(_ incomingRows: [DouyinProfilePostRow]) async {
        guard !incomingRows.isEmpty else { return }
        let snapshotItems = items
        let snapshotSeen = seenIDs
        let rows = incomingRows
        let merged = await Task.detached(priority: .userInitiated) { [snapshotItems, snapshotSeen, rows] in
            var nextItems = snapshotItems
            var nextSeen = snapshotSeen
            for row in rows where nextSeen.insert(row.awemeId).inserted {
                nextItems.append(row)
            }
            return (nextItems, nextSeen)
        }.value
        items = merged.0
        seenIDs = merged.1
    }

    private func scheduleMetadataEnrichment(limit: Int) {
        guard limit > 0 else { return }
        metadataEnrichmentTask?.cancel()
        let snapshot = items
        metadataEnrichmentTask = Task.detached(priority: .utility) { [snapshot, limit, cookieFile = cookieFileURL(), binaries = vm.coordinator.binaries] in
            guard let ytdlp = try? binaries.ytdlpPath() else { return }
            let targetRows = snapshot.filter { row in
                let missingThumbnail = row.thumbnail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                let genericTitle = row.title.hasPrefix("Douyin post ")
                return missingThumbnail || genericTitle
            }
            let target = Array(targetRows.prefix(limit))
            var updates: [String: DouyinProfilePostRow] = [:]
            for row in target {
                if Task.isCancelled { break }
                guard let meta = await MetadataFetcher.fetch(url: row.pageURL, ytdlp: ytdlp, cookieFile: cookieFile) else { continue }
                let nextTitle = row.title.hasPrefix("Douyin post ") ? meta.title : row.title
                let nextAuthor = row.author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? meta.channelName : row.author
                let nextThumb = row.thumbnail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? meta.thumbnailURL : row.thumbnail
                updates[row.awemeId] = DouyinProfilePostRow(
                    awemeId: row.awemeId,
                    title: nextTitle,
                    author: nextAuthor,
                    thumbnail: nextThumb,
                    pageURL: row.pageURL
                )
            }
            let resolvedUpdates = updates
            let indexByID = Dictionary(uniqueKeysWithValues: snapshot.enumerated().map { ($0.element.awemeId, $0.offset) })
            await MainActor.run {
                guard !resolvedUpdates.isEmpty else { return }
                var nextItems = items
                var changed = false
                for (id, updated) in resolvedUpdates {
                    guard let index = indexByID[id], nextItems.indices.contains(index) else { continue }
                    if nextItems[index] != updated {
                        nextItems[index] = updated
                        changed = true
                    }
                }
                if changed {
                    items = nextItems
                }
            }
        }
    }

    private func handleDownload() async {
        guard !selected.isEmpty else { return }
        busy = true
        let selectionCount = selected.count
        let snapshotItems = items
        let snapshotSelected = selected
        let selection = await Task.detached(priority: .userInitiated) { [snapshotItems, snapshotSelected] in
            let selectedIDs = snapshotSelected
            let rows = snapshotItems.filter { selectedIDs.contains($0.awemeId) }
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
            return (title, entries)
        }.value
        let quality = AppGroupSettings.defaults.integer(forKey: "downloadDefaultVideoQuality")
        let preset = DownloadFormatPreset.fromDefaultQualitySetting(quality == 0 ? 1080 : quality)
        Task.detached(priority: .userInitiated) { [selection, preset, vm] in
            do {
                try await vm.enqueueBulk(
                    entries: selection.1,
                    collectionTitle: selection.0,
                    kind: .douyinProfile,
                    formatArgs: preset.ytdlpArgs()
                )
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                }
            }
        }
        await MainActor.run {
            onClose()
            busy = false
            CopyHUD.show(selectionCount == 1 ? "Added to Downloads" : "Added \(selectionCount) to queue", symbol: "arrow.down.circle.fill")
        }
    }

    private func cookieFileURL() -> URL? {
        let base = AppGroup.containerURL().appendingPathComponent("cookies", isDirectory: true)
        // Prefer extension-synced cookies (freshest); fall back to manually imported file
        for name in ["downloader-extension-cookies.txt", "downloader-cookies.txt"] {
            let url = base.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
