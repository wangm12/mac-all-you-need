import AppKit
import Core
import Foundation
import Platform
import SwiftUI

@MainActor
@Observable
final class DownloaderViewModel {
    let coordinator: DownloadCoordinator
    var rows: [DownloadRecord] = []
    var presentation = DownloadsListPresentation()
    var liveProgress: [String: DownloadProgress] = [:]
    var liveStatus: [String: String] = [:]
    var cookieWarning: String?
    var presentedPicker: DownloadPickerPresentation?
    var pendingURLs: [PendingDownloadURL] = []
    private var pendingURLHead = 0
    var interruptedRecoveryCount = 0
    var selectedIDs: Set<String> = []
    var anchorID: String? = nil
    private var rowIndexByID: [String: Int] = [:]

    // Sliding window speed calculation (5 s window, 1 s display throttle)
    private struct SpeedSample {
        let timestamp: Date
        let bytes: Int64
    }
    private var speedSamples: [String: [SpeedSample]] = [:]
    private var lastDisplayUpdate: [String: Date] = [:]
    private static let speedWindow: TimeInterval = 5
    private static let displayInterval: TimeInterval = 1

    // Actual on-disk path for partial file cleanup on delete
    private var liveDestination: [String: String] = [:]
    private var formatDispatchPayloads: [String: DispatchRoutePayload] = [:]
    private var routeRequestTokens: [NSObjectProtocol] = []
    private var refreshTask: Task<Void, Never>?
    private var refreshCoalescer = RefreshCoalescer()
    private var pollingTask: Task<Void, Never>?
    private var lastSnapshotSummary: DownloadStore.SnapshotSummary?
    private var bulkRefreshPending = false
    private static let pollingInterval: UInt64 = 10_000_000_000
    private var pendingStateChanges: [String: String?] = [:]
    private var stateChangeTask: Task<Void, Never>?
    private static let stateChangeCoalesceInterval: UInt64 = 100_000_000

    enum RefreshKind {
        case regular
        case bulk

        var priority: Int {
            switch self {
            case .regular: return 0
            case .bulk: return 1
            }
        }
    }

    struct RefreshCoalescer {
        private(set) var pendingKind: RefreshKind = .regular
        private(set) var inFlight = false
        private(set) var pendingRefresh = false

        mutating func schedule(kind: RefreshKind) {
            if kind.priority > pendingKind.priority {
                pendingKind = kind
            }
            if inFlight {
                pendingRefresh = true
            }
        }

        mutating func startIfNeeded() -> (delay: UInt64, kind: RefreshKind)? {
            guard !inFlight else { return nil }
            inFlight = true
            let delay: UInt64 = pendingKind == .bulk ? 750_000_000 : 300_000_000
            return (delay, pendingKind)
        }

        mutating func finish() -> (shouldReschedule: Bool, kind: RefreshKind) {
            inFlight = false
            let kind = pendingKind
            pendingKind = .regular
            let shouldReschedule = pendingRefresh
            pendingRefresh = false
            return (shouldReschedule, kind)
        }
    }

    // Phase 7 W1: per-component NC adapter folds the 5 raw observers into
    // a tiny typed surface. Lives below as a private inline type.
    private let notifications = DownloaderNotificationObservers()

    init(coordinator: DownloadCoordinator) {
        self.coordinator = coordinator
        notifications.onProgress = { [weak self] id, progress in
            self?.handleProgress(id: id, p: progress)
        }
        notifications.onPhase = { [weak self] id, phase in
            self?.liveStatus[id] = phase
        }
        notifications.onStateChanged = { [weak self] id, state in
            Task { @MainActor in self?.enqueueStateChange(id: id, state: state) }
        }
        notifications.onInterruptedRecovery = { [weak self] count in
            self?.interruptedRecoveryCount = count
        }
        notifications.onDestinationPath = { [weak self] id, path in
            self?.liveDestination[id] = path
        }
        notifications.onBulkChanged = { [weak self] in
            Task { @MainActor in
                self?.bulkRefreshPending = true
                self?.scheduleRefresh(kind: .bulk)
            }
        }
        notifications.onCookieWarning = { [weak self] message in
            self?.cookieWarning = message ?? "Some browser profiles could not be imported. Downloads requiring login may fail."
        }
        observeRouteRequests()
        Task { await self.refresh() }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.pollingInterval)
                guard !Task.isCancelled else { return }
                await self?.refresh()
            }
        }
    }

    private func scheduleRefresh(kind: RefreshKind = .regular) {
        refreshCoalescer.schedule(kind: kind)
        guard refreshTask == nil else { return }
        refreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.refreshTask = nil }
            await self.runScheduledRefresh()
        }
    }

    private func enqueueStateChange(id: String, state: String?) {
        pendingStateChanges[id] = state
        guard stateChangeTask == nil else { return }
        stateChangeTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.stateChangeTask = nil }
            try? await Task.sleep(nanoseconds: Self.stateChangeCoalesceInterval)
            self.flushPendingStateChanges()
        }
    }

    private func flushPendingStateChanges() {
        guard !pendingStateChanges.isEmpty else { return }
        let changes = pendingStateChanges
        pendingStateChanges.removeAll(keepingCapacity: true)
        var needsRefresh = false
        for (id, state) in changes {
            if applyStateChange(id: id, state: state) {
                needsRefresh = true
            }
        }
        if needsRefresh {
            scheduleRefresh()
        }
    }

    private func runScheduledRefresh() async {
        guard let scheduled = refreshCoalescer.startIfNeeded() else { return }
        try? await Task.sleep(nanoseconds: scheduled.delay)
        guard !Task.isCancelled else {
            _ = refreshCoalescer.finish()
            return
        }
        await refresh()
        let result = refreshCoalescer.finish()
        if result.shouldReschedule {
            scheduleRefresh(kind: result.kind)
        }
    }

    // MARK: - Speed smoothing

    private func handleProgress(id: String, p: DownloadProgress) {
        let now = Date()

        // Add sample if we have byte count data
        if let bytes = p.downloadedBytes {
            var samples = speedSamples[id] ?? []
            samples.append(SpeedSample(timestamp: now, bytes: bytes))
            // Prune samples older than the window
            let cutoff = now.addingTimeInterval(-Self.speedWindow)
            samples = samples.filter { $0.timestamp >= cutoff }
            speedSamples[id] = samples
        }

        // Throttle display updates to once per second
        let lastUpdate = lastDisplayUpdate[id] ?? .distantPast
        guard now.timeIntervalSince(lastUpdate) >= Self.displayInterval else { return }
        lastDisplayUpdate[id] = now

        // Compute window speed (bytes/s)
        let windowSpeed: Double? = {
            guard let samples = speedSamples[id], samples.count >= 2,
                  let first = samples.first, let last = samples.last else { return p.speedBytesPerSec }
            let dt = last.timestamp.timeIntervalSince(first.timestamp)
            guard dt > 0 else { return p.speedBytesPerSec }
            return Double(last.bytes - first.bytes) / dt
        }()

        // Compute stable ETA from window speed and remaining bytes
        let stableETA: Int? = {
            guard let speed = windowSpeed, speed > 0,
                  let total = p.totalBytes,
                  let downloaded = p.downloadedBytes else { return p.etaSeconds }
            let remaining = max(0, total - downloaded)
            return Int(Double(remaining) / speed)
        }()

        liveProgress[id] = DownloadProgress(
            fraction: p.fraction,
            speedBytesPerSec: windowSpeed,
            etaSeconds: stableETA,
            downloadedBytes: p.downloadedBytes,
            totalBytes: p.totalBytes
        )
    }

    @discardableResult
    private func applyStateChange(id: String, state: String?) -> Bool {
        guard let index = rowIndexByID[id] else {
            return !bulkRefreshPending
        }
        guard let state, let nextState = DownloadState(rawValue: state) else {
            removeDeletedRow(id: id)
            return true
        }
        guard rows[index].state != nextState else { return false }
        rows[index].state = nextState
        rows[index].modified = Date()
        if ["completed", "failed", "paused"].contains(state) {
            liveProgress.removeValue(forKey: id)
            liveStatus.removeValue(forKey: id)
            speedSamples.removeValue(forKey: id)
            lastDisplayUpdate.removeValue(forKey: id)
        }
        return true
    }

    private func removeDeletedRow(id: String) {
        guard rowIndexByID[id] != nil else { return }
        rows.removeAll { $0.id.rawValue == id }
        liveProgress.removeValue(forKey: id)
        liveStatus.removeValue(forKey: id)
        speedSamples.removeValue(forKey: id)
        lastDisplayUpdate.removeValue(forKey: id)
        liveDestination.removeValue(forKey: id)
        selectedIDs.remove(id)
        if anchorID == id {
            anchorID = selectedIDs.first
        }
        rowIndexByID = Dictionary(uniqueKeysWithValues: rows.enumerated().map { ($0.element.id.rawValue, $0.offset) })
        presentation = DownloadsListPresentation(rows: rows, liveProgress: liveProgress)
    }

    // MARK: - Public actions

    func dismissCookieWarning() { cookieWarning = nil }

    private func observeRouteRequests() {
        let handler: (Notification) -> Void = { [weak self] note in
            guard let url = note.userInfo?["url"] as? String else { return }
            let payload = DispatchRoutePayload(
                mediaType: note.userInfo?["type"] as? String,
                referer: note.userInfo?["referer"] as? String,
                headers: note.userInfo?["headers"] as? [String: String],
                title: note.userInfo?["title"] as? String
            )
            Task { @MainActor in await self?.routeURL(url, dispatch: payload) }
        }

        routeRequestTokens.append(
            NotificationCenter.default.addObserver(
                forName: .downloadRouteRequested,
                object: nil,
                queue: .main,
                using: handler
            )
        )
        routeRequestTokens.append(
            DistributedNotificationCenter.default().addObserver(
                forName: .downloadRouteRequested,
                object: nil,
                queue: .main,
                using: handler
            )
        )
    }

    static func clipboardVideoURL() -> String? {
        let pasteboard = NSPasteboard.general

        if let text = pasteboard.string(forType: .string) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if let url = downloadableURL(in: trimmed) {
                return url
            }
        }

        // Browser "Copy Link" often writes a URL object without a plain-string type.
        if let url = pasteboard.readObjects(forClasses: [NSURL.self], options: nil)?.first as? URL {
            return downloadableURL(in: url.absoluteString)
        }

        return nil
    }

    private static func downloadableURL(in text: String) -> String? {
        URLDetector.firstDownloadableURL(in: text)
    }

    private static func normalizedDownloadInput(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        let urls = URLDetector.allDownloadableURLs(in: trimmed)
        if urls.count > 1 {
            return urls.joined(separator: "\n")
        }
        if let first = urls.first {
            return first
        }
        return trimmed
    }

    func enqueueClipboardURL() async {
        guard let url = Self.clipboardVideoURL() else {
            CopyHUD.show("No video URL", symbol: "exclamationmark.triangle.fill")
            return
        }
        await routeURL(url)
    }

    private func routeURL(_ rawInput: String, dispatch: DispatchRoutePayload? = nil) async {
        let trimmed = Self.normalizedDownloadInput(rawInput)
        guard !trimmed.isEmpty else { return }

        if presentedPicker != nil {
            pendingURLs.append(PendingDownloadURL(url: trimmed))
            return
        }

        guard let route = DownloadURLClassifier.route(for: trimmed) else {
            CopyHUD.show("Invalid URL", symbol: "exclamationmark.triangle.fill")
            return
        }
        if shouldBlockForMissingExtensionCookies(route: route) {
            cookieWarning = "Mac All You Need Companion mode is selected but no synced cookies were found. Use Downloads > Settings > Mac All You Need Companion, or switch back to Browser Auto."
            CopyHUD.show("Sync Companion cookies first", symbol: "exclamationmark.triangle.fill")
            return
        }

        switch route {
        case let .multiURL(urls):
            guard let first = urls.first else { return }
            pendingURLs.append(contentsOf: urls.dropFirst().map { PendingDownloadURL(url: $0) })
            await routeURL(first, dispatch: dispatch)
        case let .douyinProfile(url):
            presentedPicker = .douyinProfile(url: url)
        case let .collection(url):
            presentedPicker = .collection(url: url)
        case let .single(url):
            guard URL(string: url)?.scheme != nil else {
                CopyHUD.show("Invalid URL", symbol: "exclamationmark.triangle.fill")
                return
            }
            if shouldAutoDownloadWithoutFormatSheet || dispatch != nil {
                let quality = AppGroupSettings.defaults.integer(forKey: "downloadDefaultVideoQuality")
                let preset = DownloadFormatPreset.fromDefaultQualitySetting(quality == 0 ? 1080 : quality)
                await coordinator.enqueue(
                    url: url,
                    title: dispatch?.title,
                    formatArgs: preset.ytdlpArgs(),
                    mediaType: dispatch?.mediaType,
                    referer: dispatch?.referer,
                    customHeaders: dispatch?.headers
                )
                scheduleRefresh()
                CopyHUD.show("Added to Downloads", symbol: "arrow.down.circle.fill")
            } else {
                await presentFormatSheet(for: url, dispatch: dispatch)
            }
        }
    }

    private func shouldBlockForMissingExtensionCookies(route: DownloadURLRoute) -> Bool {
        let mode = AppGroupSettings.defaults.string(forKey: "downloadCookieMode") ?? "browser_auto"
        guard mode == "extension_only" else { return false }
        guard !extensionCookiesAvailable() else { return false }
        switch route {
        case let .single(url), let .collection(url), let .douyinProfile(url):
            return urlNeedsAuthCookies(url)
        case let .multiURL(urls):
            return urls.contains { urlNeedsAuthCookies($0) }
        }
    }

    private func extensionCookiesAvailable() -> Bool {
        let extensionCookieFile = AppGroup.containerURL()
            .appendingPathComponent("cookies", isDirectory: true)
            .appendingPathComponent("downloader-extension-cookies.txt")
        return FileManager.default.fileExists(atPath: extensionCookieFile.path)
    }

    private func urlNeedsAuthCookies(_ rawURL: String) -> Bool {
        guard let host = URL(string: rawURL)?.host?.lowercased() else { return false }
        let authHosts = [
            "douyin.com",
            "youtube.com",
            "youtu.be",
            "instagram.com",
            "x.com",
            "twitter.com",
            "tiktok.com"
        ]
        return authHosts.contains { host == $0 || host.hasSuffix(".\($0)") }
    }

    func dismissPicker() {
        if case let .format(url, _, _) = presentedPicker {
            formatDispatchPayloads.removeValue(forKey: url)
        }
        presentedPicker = nil
        advancePendingURLQueue()
    }

    func advancePendingURLQueue() {
        guard presentedPicker == nil else { return }
        guard pendingURLHead < pendingURLs.count else { return }
        let next = pendingURLs[pendingURLHead]
        pendingURLHead += 1
        if pendingURLHead >= 32 && pendingURLHead * 2 >= pendingURLs.count {
            pendingURLs.removeFirst(pendingURLHead)
            pendingURLHead = 0
        }
        Task { await routeURL(next.url) }
    }

    func enqueueBulk(
        entries: [BulkEnqueueEntry],
        collectionTitle: String,
        kind: DownloadCollectionKind,
        formatArgs: [String]
    ) async throws {
        let result = try await Task.detached(priority: .userInitiated) { [coordinator, entries, collectionTitle, kind, formatArgs] in
            try await coordinator.enqueueBulk(
                entries: entries,
                collectionTitle: collectionTitle,
                kind: kind,
                formatArgs: formatArgs
            )
        }.value
        switch result {
        case let .local(records):
            if !records.isEmpty {
                // Merge the inserted rows immediately, but do the work off
                // the main actor so big batches still keep the UI responsive.
                await applyOptimisticBulkInsert(records)
                scheduleRefresh(kind: .bulk)
            }
        case .forwarded:
            scheduleRefresh()
        }
        let message = entries.count == 1 ? "Added to Downloads" : "Added \(entries.count) to queue"
        CopyHUD.show(message, symbol: "arrow.down.circle.fill")
    }

    func enqueueFromFormatSheet(url: String, preset: DownloadFormatPreset) async {
        let payload = formatDispatchPayloads.removeValue(forKey: url)
        let sheetMetadata: VideoMetadata?
        if case .format(let currentURL, let metadata, _) = presentedPicker, currentURL == url {
            sheetMetadata = metadata
        } else {
            sheetMetadata = nil
        }
        await coordinator.enqueue(
            url: url,
            title: payload?.title,
            formatArgs: preset.ytdlpArgs(),
            mediaType: payload?.mediaType,
            referer: payload?.referer,
            customHeaders: payload?.headers,
            videoTitle: sheetMetadata?.title,
            channelName: sheetMetadata?.channelName,
            thumbnailURL: sheetMetadata?.thumbnailURL
        )
        presentedPicker = nil
        scheduleRefresh()
        CopyHUD.show("Added to Downloads", symbol: "arrow.down.circle.fill")
        advancePendingURLQueue()
    }

    private var shouldAutoDownloadWithoutFormatSheet: Bool {
        AppGroupSettings.defaults.bool(forKey: "downloadAutoEnqueueSingleURL")
    }

    private func presentFormatSheet(for url: String, dispatch: DispatchRoutePayload?) async {
        if let dispatch {
            formatDispatchPayloads[url] = dispatch
        }
        presentedPicker = .format(url: url, metadata: nil, isRefiningResolutions: false)

        if isDouyinURL(url) {
            let cookieFile = existingCookieFileForMetadata()
            if let douyinMeta = await DouyinVideoClient.fetchMetadata(url: url, cookieFile: cookieFile) {
                guard case .format(let u, let current, _) = presentedPicker, u == url else { return }
                let merged = current?.merging(douyinMeta) ?? douyinMeta
                presentedPicker = .format(url: url, metadata: merged, isRefiningResolutions: false)
            }
            return
        }

        // Stage 1: oEmbed (YouTube, ~100ms) — title + thumbnail without yt-dlp.
        let quick = await MetadataFetcher.fetchOEmbed(url: url)

        guard let ytdlpPath = try? coordinator.binaries.ytdlpPath() else {
            if case .format(let u, _, _) = presentedPicker, u == url {
                presentedPicker = .format(url: url, metadata: quick, isRefiningResolutions: false)
            }
            return
        }

        let cookieFile = existingCookieFileForMetadata()
        if case .format(let u, _, _) = presentedPicker, u == url {
            presentedPicker = .format(url: url, metadata: quick, isRefiningResolutions: true)
        }
        Task { [weak self] in
            let full = await MetadataFetcher.fetchFormatHeights(
                url: url,
                ytdlp: ytdlpPath,
                cookieFile: cookieFile
            )
            await MainActor.run {
                guard let self else { return }
                guard case .format(let currentURL, let current, _) = self.presentedPicker,
                      currentURL == url else { return }
                let merged = full.map { current?.merging($0) ?? $0 } ?? current
                self.presentedPicker = .format(
                    url: url,
                    metadata: merged,
                    isRefiningResolutions: false
                )
            }
        }
    }

    /// Cookie files already on disk — avoids a slow browser import during format picking.
    private func existingCookieFileForMetadata() -> URL? {
        mergedCookieFileURL() ?? extensionCookieFileURL()
    }

    private func cookieFileForMetadata() -> URL? {
        if let merged = mergedCookieFileURL() { return merged }
        let (args, _) = coordinatorCookieArgs()
        return cookieFileURL(from: args) ?? extensionCookieFileURL()
    }

    // Returns whichever synced/imported cookie file already exists on disk —
    // no Chrome DB import, safe to call from any context.
    private func existingCookieFileURL() -> URL? {
        mergedCookieFileURL() ?? extensionCookieFileURL()
    }

    private func mergedCookieFileURL() -> URL? {
        let url = AppGroup.containerURL()
            .appendingPathComponent("cookies", isDirectory: true)
            .appendingPathComponent("downloader-cookies.txt")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private func extensionCookieFileURL() -> URL? {
        let url = AppGroup.containerURL()
            .appendingPathComponent("cookies", isDirectory: true)
            .appendingPathComponent("downloader-extension-cookies.txt")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private func isDouyinURL(_ url: String) -> Bool {
        url.localizedCaseInsensitiveContains("douyin.com")
    }

    private func coordinatorCookieArgs() -> ([String], Bool) {
        DownloadCookieConfiguration.makeCookieArgs()
    }

    private func cookieFileURL(from cookieArgsList: [String]) -> URL? {
        guard let idx = cookieArgsList.firstIndex(of: "--cookies"),
              cookieArgsList.indices.contains(idx + 1) else { return nil }
        return URL(fileURLWithPath: cookieArgsList[idx + 1])
    }

    func add(url: String) async {
        await routeURL(url)
    }

    #if DEBUG
    func seedSyntheticDownloads(count: Int) async {
        guard count > 0 else { return }
        let entries = (1...count).map { index in
            BulkEnqueueEntry(
                pageURL: "https://example.com/demo/\(index)",
                title: "Demo Video \(index)",
                channel: "Demo Channel",
                thumbnailURL: nil,
                durationSeconds: 180,
                playlistIndex: index
            )
        }
        do {
            _ = try await enqueueBulk(
                entries: entries,
                collectionTitle: "UI Audit Demo Bulk",
                kind: .multiURL,
                formatArgs: []
            )
        } catch {
            logBulkSeedFailure(error)
        }
    }

    private func logBulkSeedFailure(_ error: Error) {
        Logging.logger(for: "downloader", category: "view-model")
            .warning("synthetic bulk seed failed: \(error.localizedDescription)")
    }
    #endif

    func refresh() async {
        let knownSummary = lastSnapshotSummary
        let store = coordinator.store
        let currentRows = rows
        let allowBulkSync = bulkRefreshPending
        let refreshResult = await Task.detached(priority: .utility) { [store, knownSummary, currentRows, allowBulkSync] () -> (DownloadStore.SnapshotSummary?, [DownloadRecord]?) in
            guard let summary = try? store.snapshotSummary() else {
                return (nil, nil)
            }
            guard Self.needsFullRefresh(newSummary: summary, previousSummary: knownSummary) else {
                return (summary, nil)
            }
            let countChanged = summary.count != knownSummary?.count
            // Large queues already receive incremental state updates through
            // notifications. Avoid turning every modified timestamp bump into a
            // full fetch/rebuild when the list is big.
            if currentRows.count >= 64, !currentRows.isEmpty, !allowBulkSync, !countChanged {
                return (summary, nil)
            }
            if currentRows.count >= 64, !allowBulkSync, countChanged {
                let existingIDs = Set(currentRows.map { $0.id.rawValue })
                guard let ids = try? store.list() else {
                    return (summary, nil)
                }
                let storeIDSet = Set(ids.map(\.rawValue))
                let missingIDs = ids.filter { !existingIDs.contains($0.rawValue) }
                if missingIDs.isEmpty, currentRows.count == ids.count {
                    return (summary, nil)
                }
                if missingIDs.count >= 24 || currentRows.count != ids.count {
                    return (summary, try? store.fetchAll())
                }
                var mergedRows = currentRows.filter { storeIDSet.contains($0.id.rawValue) }
                let missingRows: [DownloadRecord] = missingIDs.compactMap { try? store.fetch(id: $0) }
                mergedRows.insert(contentsOf: missingRows, at: 0)
                return (summary, mergedRows)
            }
            let existingIDs = Set(currentRows.map { $0.id.rawValue })
            guard let ids = try? store.list() else {
                return (summary, nil)
            }
            if ids.count >= 64 || currentRows.isEmpty {
                return (summary, try? store.fetchAll())
            }
            let storeIDSet = Set(ids.map(\.rawValue))
            var mergedRows = currentRows.filter { storeIDSet.contains($0.id.rawValue) }
            let missingIDs = ids.filter { !existingIDs.contains($0.rawValue) }
            if missingIDs.count >= 24 {
                return (summary, try? store.fetchAll())
            }
            if !missingIDs.isEmpty {
                let missingRows: [DownloadRecord] = missingIDs.compactMap { try? store.fetch(id: $0) }
                mergedRows.append(contentsOf: missingRows)
            }
            return (summary, mergedRows)
        }.value
        if let summary = refreshResult.0 {
            lastSnapshotSummary = summary
        }
        if let snapshot = refreshResult.1 {
            let store = coordinator.store
            let hydrated = await Task.detached(priority: .utility) { [snapshot, store] () -> [DownloadRecord] in
                snapshot.map { record in
                    let next = DownloadMetadataFallback.hydrate(record)
                    if next != record {
                        try? store.update(next)
                    }
                    return next
                }
            }.value
            rows = hydrated
            rebuildRowIndexMap()
            presentation = await Task.detached(priority: .utility) { [liveProgress, hydrated] in
                DownloadsListPresentation(rows: hydrated, liveProgress: liveProgress)
            }.value
        }
        bulkRefreshPending = false
    }

    private func rebuildRowIndexMap() {
        rowIndexByID = Dictionary(uniqueKeysWithValues: rows.enumerated().map { ($0.element.id.rawValue, $0.offset) })
    }

    private func applyOptimisticBulkInsert(_ records: [DownloadRecord]) async {
        guard !records.isEmpty else { return }
        let snapshotProgress = liveProgress
        let sortedIncoming = records.sorted { lhs, rhs in
            if lhs.created != rhs.created { return lhs.created > rhs.created }
            return lhs.id.rawValue < rhs.id.rawValue
        }

        if records.count <= 64 {
            let snapshotRows = rows
            let merged = await Task.detached(priority: .userInitiated) { [snapshotRows, snapshotProgress, sortedIncoming] in
                let incomingIDs = Set(sortedIncoming.map { $0.id.rawValue })
                var nextRows = snapshotRows
                nextRows.removeAll { incomingIDs.contains($0.id.rawValue) }
                nextRows.insert(contentsOf: sortedIncoming, at: 0)
                let presentation = DownloadsListPresentation(rows: nextRows, liveProgress: snapshotProgress)
                let rowIndexByID = Dictionary(uniqueKeysWithValues: nextRows.enumerated().map { ($0.element.id.rawValue, $0.offset) })
                return (nextRows, presentation, rowIndexByID)
            }.value
            rows = merged.0
            presentation = merged.1
            rowIndexByID = merged.2
            return
        }

        let existingRows = rows
        let incomingIDs = Set(sortedIncoming.map { $0.id.rawValue })
        let remainingRows = existingRows.filter { !incomingIDs.contains($0.id.rawValue) }
        var nextRows: [DownloadRecord] = []
        nextRows.reserveCapacity(remainingRows.count + sortedIncoming.count)
        nextRows.append(contentsOf: sortedIncoming)
        nextRows.append(contentsOf: remainingRows)

        rows = nextRows
        rowIndexByID = Dictionary(uniqueKeysWithValues: nextRows.enumerated().map { ($0.element.id.rawValue, $0.offset) })
        bulkRefreshPending = true
        scheduleRefresh(kind: .bulk)
    }

    nonisolated static func needsFullRefresh(
        newSummary: DownloadStore.SnapshotSummary,
        previousSummary: DownloadStore.SnapshotSummary?
    ) -> Bool {
        newSummary.count != previousSummary?.count || newSummary.modifiedMax != previousSummary?.modifiedMax
    }

    nonisolated private static func snapshotSummary(for rows: [DownloadRecord]) -> DownloadStore.SnapshotSummary {
        DownloadStore.SnapshotSummary(
            count: rows.count,
            modifiedMax: rows
                .map { Int($0.modified.timeIntervalSince1970 * 1000) }
                .max()
        )
    }

    func pauseCollection(id: String) async {
        await coordinator.pauseCollection(id: id)
        scheduleRefresh()
    }

    func resumeCollection(id: String) async {
        await coordinator.resumeCollection(id: id)
        scheduleRefresh()
        CopyHUD.show("Resumed collection", symbol: "play.circle.fill")
    }

    func deleteCollection(id: String, deleteFiles: Bool) async {
        let collectionRows = rows.filter { $0.collectionID == id }
        let collectionIDs = collectionRows.map(\.id)
        if !collectionIDs.isEmpty {
            let collectionIDSet = Set(collectionIDs.map(\.rawValue))
            selectedIDs.subtract(collectionIDSet)
            if let anchorID, collectionIDSet.contains(anchorID) {
                self.anchorID = selectedIDs.first
            }
            rows.removeAll { $0.collectionID == id }
            for rawID in collectionIDSet {
                liveProgress.removeValue(forKey: rawID)
                liveStatus.removeValue(forKey: rawID)
                speedSamples.removeValue(forKey: rawID)
                lastDisplayUpdate.removeValue(forKey: rawID)
                liveDestination.removeValue(forKey: rawID)
            }
            rowIndexByID = Dictionary(uniqueKeysWithValues: rows.enumerated().map { ($0.element.id.rawValue, $0.offset) })
            presentation = DownloadsListPresentation(rows: rows, liveProgress: liveProgress)
        }
        await coordinator.deleteCollection(id: id, deleteFiles: deleteFiles)
        scheduleRefresh()
        CopyHUD.show(deleteFiles ? "Deleted collection and files" : "Removed collection", symbol: "trash.fill")
    }

    func resumeInterruptedDownloads() async {
        let paused = rows.filter { $0.state == .paused }
        await coordinator.resumeDownloads(records: paused)
        interruptedRecoveryCount = 0
        scheduleRefresh()
    }

    func retry(record: DownloadRecord) async {
        CopyHUD.show("Retrying", symbol: "arrow.clockwise.circle.fill")
        await coordinator.reenqueue(record: record)
        scheduleRefresh()
    }

    func retryFailed(in records: [DownloadRecord]) async {
        let failedRecords = records.filter { $0.state == .failed }
        guard !failedRecords.isEmpty else { return }
        let message = failedRecords.count == 1 ? "Retrying" : "Retrying \(failedRecords.count)"
        CopyHUD.show(message, symbol: "arrow.clockwise.circle.fill")
        await coordinator.resumeDownloads(records: failedRecords)
        scheduleRefresh()
    }

    func resolvedDestinationPath(for record: DownloadRecord) -> String {
        liveDestination[record.id.rawValue] ?? record.destinationPath
    }

    func pauseAll(in records: [DownloadRecord]) async {
        let active = records.filter { $0.state == .running || $0.state == .queued }
        guard !active.isEmpty else { return }
        CopyHUD.show(active.count == 1 ? "Pausing" : "Pausing \(active.count)", symbol: "pause.circle.fill")
        let ids = active.map(\.id)
        for record in active where record.state == .running {
            liveProgress.removeValue(forKey: record.id.rawValue)
            liveStatus.removeValue(forKey: record.id.rawValue)
            speedSamples.removeValue(forKey: record.id.rawValue)
            lastDisplayUpdate.removeValue(forKey: record.id.rawValue)
        }
        await coordinator.pauseDownloads(ids: ids)
        scheduleRefresh()
    }

    func deleteWithFiles(_ records: [DownloadRecord]) async {
        guard !records.isEmpty else { return }
        CopyHUD.show(records.count == 1 ? "Deleted" : "Deleted \(records.count)", symbol: "trash.fill")
        await coordinator.deleteDownloadsWithFiles(records: records)
        scheduleRefresh()
    }

    func resumeAll(in records: [DownloadRecord]) async {
        let paused = records.filter { $0.state == .paused }
        guard !paused.isEmpty else { return }
        CopyHUD.show(paused.count == 1 ? "Resuming" : "Resuming \(paused.count)", symbol: "play.circle.fill")
        await coordinator.resumeDownloads(records: paused)
        scheduleRefresh()
    }

    func startAll(in records: [DownloadRecord]) async {
        let paused = records.filter { $0.state == .paused }
        let failed = records.filter { $0.state == .failed }
        let queued = records.filter { $0.state == .queued }
        guard !paused.isEmpty || !failed.isEmpty || !queued.isEmpty else { return }
        CopyHUD.show("Starting", symbol: "play.circle.fill")
        await coordinator.resumeDownloads(records: paused + failed + queued)
        scheduleRefresh()
    }

    func clearAll(in records: [DownloadRecord]) async {
        guard !records.isEmpty else { return }
        let ids = records.map(\.id)
        CopyHUD.show(ids.count == 1 ? "Cleared" : "Cleared \(ids.count)", symbol: "trash.fill")
        await delete(ids: ids)
    }

    func cancel(id: RecordID) async {
        liveProgress.removeValue(forKey: id.rawValue)
        liveStatus.removeValue(forKey: id.rawValue)
        speedSamples.removeValue(forKey: id.rawValue)
        lastDisplayUpdate.removeValue(forKey: id.rawValue)
        liveDestination.removeValue(forKey: id.rawValue)
        await coordinator.cancelDownload(id: id)
        scheduleRefresh()
    }

    func pause(id: RecordID) async {
        liveProgress.removeValue(forKey: id.rawValue)
        liveStatus.removeValue(forKey: id.rawValue)
        speedSamples.removeValue(forKey: id.rawValue)
        lastDisplayUpdate.removeValue(forKey: id.rawValue)
        await coordinator.pauseDownload(id: id)
        scheduleRefresh()
        CopyHUD.show("Paused", symbol: "pause.circle.fill")
    }

    func resume(id: RecordID) async {
        await coordinator.resumeDownload(id: id)
        scheduleRefresh()
        CopyHUD.show("Resumed", symbol: "play.circle.fill")
    }

    func delete(ids: [RecordID]) async {
        guard !ids.isEmpty else { return }
        CopyHUD.show(ids.count == 1 ? "Deleting" : "Deleting \(ids.count)", symbol: "trash.fill")
        let snapshotRows = rows
        let snapshotLiveDestination = liveDestination
        let snapshotLiveProgress = liveProgress
        let snapshotLiveStatus = liveStatus
        let snapshotSpeedSamples = speedSamples
        let snapshotLastDisplayUpdate = lastDisplayUpdate
        let idSet = Set(ids)
        let rawIDs = Set(ids.map(\.rawValue))
        selectedIDs.subtract(rawIDs)
        let result = await Task.detached(priority: .userInitiated) { [snapshotRows, snapshotLiveDestination, snapshotLiveProgress, snapshotLiveStatus, snapshotSpeedSamples, snapshotLastDisplayUpdate, idSet, rawIDs] in
            let pathsToDelete = snapshotRows.reduce(into: [RecordID: String]()) { result, row in
                guard idSet.contains(row.id) else { return }
                if let path = snapshotLiveDestination[row.id.rawValue] {
                    result[row.id] = path
                } else if !row.destinationPath.isEmpty {
                    result[row.id] = row.destinationPath
                }
            }
            let nextRows = snapshotRows.filter { !idSet.contains($0.id) }
            var nextLiveProgress = snapshotLiveProgress
            var nextLiveStatus = snapshotLiveStatus
            var nextSpeedSamples = snapshotSpeedSamples
            var nextLastDisplayUpdate = snapshotLastDisplayUpdate
            for rawID in rawIDs {
                nextLiveProgress.removeValue(forKey: rawID)
                nextLiveStatus.removeValue(forKey: rawID)
                nextSpeedSamples.removeValue(forKey: rawID)
                nextLastDisplayUpdate.removeValue(forKey: rawID)
            }
            let rowIndexByID = Dictionary(uniqueKeysWithValues: nextRows.enumerated().map { ($0.element.id.rawValue, $0.offset) })
            return (pathsToDelete, nextRows, nextLiveProgress, nextLiveStatus, nextSpeedSamples, nextLastDisplayUpdate, rowIndexByID)
        }.value
        let pathsToDelete = result.0
        rows = result.1
        liveProgress = result.2
        liveStatus = result.3
        speedSamples = result.4
        lastDisplayUpdate = result.5
        rowIndexByID = result.6
        presentation = DownloadsListPresentation(rows: rows, liveProgress: liveProgress)

        await coordinator.deleteDownloads(ids: ids)

        for (id, path) in pathsToDelete {
            guard idSet.contains(id) else { continue }
            // Remove the partial file yt-dlp may have left on disk.
            try? FileManager.default.removeItem(atPath: path)
            try? FileManager.default.removeItem(atPath: path + ".part")
            try? FileManager.default.removeItem(atPath: path + ".ytdl")
        }
        scheduleRefresh()
        let msg = ids.count == 1 ? "Deleted" : "Deleted \(ids.count)"
        CopyHUD.show(msg, symbol: "trash.fill")
    }
}

struct DownloadsListPresentation: Equatable {
    struct GroupState: Equatable {
        let hasActive: Bool
        let resumable: Bool
        let runningCount: Int
    }

    private(set) var visibleRowsByFilter: [DownloadsListFilter: [DownloadRecord]] = [:]
    private(set) var listItemsByFilter: [DownloadsListFilter: [DownloadCollectionGrouping.ListItem]] = [:]
    private(set) var bulkActionsByFilter: [DownloadsListFilter: [DownloadsQueuePresentation.BulkAction]] = [:]
    private(set) var hasFailedByFilter: [DownloadsListFilter: Bool] = [:]
    private(set) var shouldShowThumbnailsByFilter: [DownloadsListFilter: Bool] = [:]
    private(set) var groupProgressByID: [String: Double] = [:]
    private(set) var groupSpeedByID: [String: Double] = [:]
    private(set) var groupStateByID: [String: GroupState] = [:]

    init(rows: [DownloadRecord] = [], liveProgress: [String: DownloadProgress] = [:]) {
        let groupBuckets: [String: [DownloadRecord]] = rows.reduce(into: [:]) { buckets, record in
            guard let collectionID = record.collectionID else { return }
            buckets[collectionID, default: []].append(record)
        }
        var allVisible: [DownloadRecord] = []
        var activeVisible: [DownloadRecord] = []
        var completedVisible: [DownloadRecord] = []
        allVisible.reserveCapacity(rows.count)
        activeVisible.reserveCapacity(rows.count)
        completedVisible.reserveCapacity(rows.count)
        for record in rows {
            allVisible.append(record)
            if DownloadsListFilter.activeQueue.includes(record.state) {
                activeVisible.append(record)
            }
            if record.state == .completed {
                completedVisible.append(record)
            }
        }
        allVisible.sort { lhs, rhs in
            let lhsActive = DownloadsListFilter.activeQueue.includes(lhs.state)
            let rhsActive = DownloadsListFilter.activeQueue.includes(rhs.state)
            if lhsActive != rhsActive { return lhsActive && !rhsActive }
            return lhs.modified > rhs.modified
        }
        visibleRowsByFilter[.all] = allVisible
        visibleRowsByFilter[.activeQueue] = activeVisible
        visibleRowsByFilter[.completed] = completedVisible

        listItemsByFilter[.all] = DownloadCollectionGrouping.items(from: allVisible)
        listItemsByFilter[.activeQueue] = DownloadCollectionGrouping.items(from: activeVisible)
        listItemsByFilter[.completed] = DownloadCollectionGrouping.items(from: completedVisible)

        bulkActionsByFilter[.all] = bulkActions(for: .all, visible: allVisible)
        bulkActionsByFilter[.activeQueue] = bulkActions(for: .activeQueue, visible: activeVisible)
        bulkActionsByFilter[.completed] = bulkActions(for: .completed, visible: completedVisible)

        hasFailedByFilter[.all] = activeVisible.contains { $0.state == .failed }
        hasFailedByFilter[.activeQueue] = activeVisible.contains { $0.state == .failed }
        hasFailedByFilter[.completed] = false
        let showThumbnails = rows.count <= 100
        shouldShowThumbnailsByFilter[.all] = showThumbnails
        shouldShowThumbnailsByFilter[.activeQueue] = showThumbnails
        shouldShowThumbnailsByFilter[.completed] = showThumbnails
        for (id, records) in groupBuckets {
            var runningCount = 0
            var hasActive = false
            var resumable = false
            for record in records {
                if record.state == .running {
                    runningCount += 1
                    hasActive = true
                } else if record.state == .queued {
                    hasActive = true
                } else if record.state == .paused || record.state == .failed {
                    resumable = true
                }
            }
            groupStateByID[id] = GroupState(
                hasActive: hasActive,
                resumable: resumable,
                runningCount: runningCount
            )
            groupProgressByID[id] = DownloadCollectionGrouping.aggregateProgress(
                records: records,
                liveProgress: liveProgress
            )
            groupSpeedByID[id] = DownloadCollectionGrouping.aggregateSpeedBytes(
                records: records,
                liveProgress: liveProgress
            )
        }
    }

    func visibleRows(for filter: DownloadsListFilter) -> [DownloadRecord] {
        visibleRowsByFilter[filter] ?? []
    }

    func listItems(for filter: DownloadsListFilter) -> [DownloadCollectionGrouping.ListItem] {
        listItemsByFilter[filter] ?? []
    }

    func bulkActions(for filter: DownloadsListFilter) -> [DownloadsQueuePresentation.BulkAction] {
        bulkActionsByFilter[filter] ?? []
    }

    func hasFailed(for filter: DownloadsListFilter) -> Bool {
        hasFailedByFilter[filter] ?? false
    }

    func shouldShowThumbnails(for filter: DownloadsListFilter) -> Bool {
        shouldShowThumbnailsByFilter[filter] ?? true
    }

    func groupProgress(for id: String) -> Double? {
        groupProgressByID[id]
    }

    func groupSpeed(for id: String) -> Double? {
        groupSpeedByID[id]
    }

    func groupState(for id: String) -> GroupState? {
        groupStateByID[id]
    }

    private func bulkActions(for filter: DownloadsListFilter, visible: [DownloadRecord]) -> [DownloadsQueuePresentation.BulkAction] {
        guard !visible.isEmpty else { return [] }
        switch filter {
        case .completed:
            return [.openFolder, .clearAll]
        case .all, .activeQueue:
            let hasRunning = visible.contains { $0.state == .running }
            let hasPaused = visible.contains { $0.state == .paused }
            let hasFailed = visible.contains { $0.state == .failed }
            let hasQueued = visible.contains { $0.state == .queued }

            var actions: [DownloadsQueuePresentation.BulkAction] = []
            if hasRunning || hasQueued { actions.append(.pauseAll) }
            if hasPaused { actions.append(.resumeAll) }
            if hasFailed { actions.append(.retryAll) }
            if hasPaused || hasFailed || hasQueued { actions.append(.startAll) }
            if visible.allSatisfy({ $0.state == .completed }) {
                actions.append(.openFolder)
            }
            actions.append(.clearAll)
            return actions
        }
    }
}

private struct DispatchRoutePayload {
    let mediaType: String?
    let referer: String?
    let headers: [String: String]?
    let title: String?
}

/// Per-component NC adapter for DownloaderViewModel (Phase 7 W1).
/// Wraps the 5 raw NotificationCenter observers (`downloadProgress`,
/// `downloadPhase`, `downloadStateChanged`, `downloadDestinationPath`,
/// `cookieWarning`) in typed closures so the view-model itself doesn't
/// deal with NSObjectProtocol token plumbing.
///
/// Observers are installed for the lifetime of the view-model and torn
/// down in deinit; no start/stop pairs.
@MainActor
final class DownloaderNotificationObservers {
    var onProgress: ((String, DownloadProgress) -> Void)?
    var onPhase: ((String, String) -> Void)?
    /// state may be nil if the notification arrived without a "state" key
    /// (matches the original observer's permissive handling).
    var onStateChanged: ((String, String?) -> Void)?
    var onDestinationPath: ((String, String) -> Void)?
    var onCookieWarning: ((String?) -> Void)?
    var onInterruptedRecovery: ((Int) -> Void)?
    var onBulkChanged: (() -> Void)?

    private var tokens: [NSObjectProtocol] = []

    init() {
        registerAll()
    }

    deinit {
        for token in tokens {
            NotificationCenter.default.removeObserver(token)
        }
    }

    private func registerAll() {
        observe(.downloadProgress) { [weak self] note in
            guard let id = note.userInfo?["id"] as? String,
                  let progress = note.userInfo?["progress"] as? DownloadProgress
            else { return }
            Task { @MainActor [weak self] in self?.onProgress?(id, progress) }
        }
        observe(.downloadPhase) { [weak self] note in
            guard let id = note.userInfo?["id"] as? String,
                  let phase = note.userInfo?["phase"] as? String
            else { return }
            Task { @MainActor [weak self] in self?.onPhase?(id, phase) }
        }
        observe(.downloadStateChanged) { [weak self] note in
            guard let id = note.userInfo?["id"] as? String else { return }
            Task { @MainActor [weak self] in self?.onStateChanged?(id, note.userInfo?["state"] as? String) }
        }
        observe(.downloadDestinationPath) { [weak self] note in
            guard let id = note.userInfo?["id"] as? String,
                  let path = note.userInfo?["path"] as? String
            else { return }
            Task { @MainActor [weak self] in self?.onDestinationPath?(id, path) }
        }
        observe(.cookieWarning) { [weak self] note in
            Task { @MainActor [weak self] in self?.onCookieWarning?(note.userInfo?["message"] as? String) }
        }
        observe(.downloadInterruptedRecovery) { [weak self] note in
            let count = note.userInfo?["count"] as? Int ?? 0
            Task { @MainActor [weak self] in self?.onInterruptedRecovery?(count) }
        }
        observe(.downloadBulkChanged) { [weak self] _ in
            Task { @MainActor [weak self] in self?.onBulkChanged?() }
        }
    }

    private func observe(_ name: Notification.Name, handler: @escaping @Sendable (Notification) -> Void) {
        let distributedToken = DistributedNotificationCenter.default().addObserver(
            forName: name, object: nil, queue: .main, using: handler
        )
        tokens.append(distributedToken)
    }

}
