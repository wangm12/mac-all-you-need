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
    var liveProgress: [String: DownloadProgress] = [:]
    var liveStatus: [String: String] = [:]
    var cookieWarning: String?
    var presentedPicker: DownloadPickerPresentation?
    var pendingURLs: [PendingDownloadURL] = []
    var interruptedRecoveryCount = 0
    var selectedIDs: Set<String> = []
    var anchorID: String? = nil

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
            Task { @MainActor in
                await self?.refresh()
                if let state, ["completed", "failed", "paused"].contains(state) {
                    self?.liveProgress.removeValue(forKey: id)
                    self?.liveStatus.removeValue(forKey: id)
                    self?.speedSamples.removeValue(forKey: id)
                    self?.lastDisplayUpdate.removeValue(forKey: id)
                }
            }
        }
        notifications.onInterruptedRecovery = { [weak self] count in
            self?.interruptedRecoveryCount = count
        }
        notifications.onDestinationPath = { [weak self] id, path in
            self?.liveDestination[id] = path
        }
        notifications.onCookieWarning = { [weak self] in
            self?.cookieWarning = "Some browser profiles could not be imported. Downloads requiring login may fail."
        }
        NotificationCenter.default.addObserver(
            forName: .downloadRouteRequested,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let url = note.userInfo?["url"] as? String else { return }
            Task { @MainActor in await self?.routeURL(url) }
        }
        Task { await self.refresh() }
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

    // MARK: - Public actions

    func dismissCookieWarning() { cookieWarning = nil }

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

    func routeURL(_ rawInput: String) async {
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

        switch route {
        case let .multiURL(urls):
            guard let first = urls.first else { return }
            pendingURLs.append(contentsOf: urls.dropFirst().map { PendingDownloadURL(url: $0) })
            await routeURL(first)
        case let .douyinProfile(url):
            presentedPicker = .douyinProfile(url: url)
        case let .collection(url):
            presentedPicker = .collection(url: url)
        case let .single(url):
            guard URL(string: url)?.scheme != nil else {
                CopyHUD.show("Invalid URL", symbol: "exclamationmark.triangle.fill")
                return
            }
            if shouldAutoDownloadWithoutFormatSheet {
                let quality = AppGroupSettings.defaults.integer(forKey: "downloadDefaultVideoQuality")
                let preset = DownloadFormatPreset.fromDefaultQualitySetting(quality == 0 ? 1080 : quality)
                await coordinator.enqueue(url: url, title: nil, formatArgs: preset.ytdlpArgs())
                await refresh()
                CopyHUD.show("Added to Downloads", symbol: "arrow.down.circle.fill")
            } else {
                await presentFormatSheet(for: url)
            }
        }
    }

    func dismissPicker() {
        presentedPicker = nil
        advancePendingURLQueue()
    }

    func advancePendingURLQueue() {
        guard presentedPicker == nil, !pendingURLs.isEmpty else { return }
        let next = pendingURLs.removeFirst()
        Task { await routeURL(next.url) }
    }

    func enqueueBulk(
        entries: [BulkEnqueueEntry],
        collectionTitle: String,
        kind: DownloadCollectionKind,
        formatArgs: [String]
    ) async throws {
        try await coordinator.enqueueBulk(
            entries: entries,
            collectionTitle: collectionTitle,
            kind: kind,
            formatArgs: formatArgs
        )
        await refresh()
        let message = entries.count == 1 ? "Added to Downloads" : "Added \(entries.count) to queue"
        CopyHUD.show(message, symbol: "arrow.down.circle.fill")
    }

    func enqueueFromFormatSheet(url: String, preset: DownloadFormatPreset) async {
        await coordinator.enqueue(url: url, title: nil, formatArgs: preset.ytdlpArgs())
        presentedPicker = nil
        await refresh()
        CopyHUD.show("Added to Downloads", symbol: "arrow.down.circle.fill")
        advancePendingURLQueue()
    }

    private var shouldAutoDownloadWithoutFormatSheet: Bool {
        AppGroupSettings.defaults.bool(forKey: "downloadAutoEnqueueSingleURL")
    }

    private func presentFormatSheet(for url: String) async {
        let (cookieArgsList, cookieHadErrors) = await MainActor.run { coordinatorCookieArgs() }
        if cookieHadErrors { cookieWarning = "Some browser profiles could not be imported." }
        let cookieFileURL = cookieFileURL(from: cookieArgsList)
        guard let ytdlpPath = try? coordinator.binaries.ytdlpPath(),
              let meta = await MetadataFetcher.fetch(url: url, ytdlp: ytdlpPath, cookieFile: cookieFileURL)
        else {
            let quality = AppGroupSettings.defaults.integer(forKey: "downloadDefaultVideoQuality")
            let preset = DownloadFormatPreset.fromDefaultQualitySetting(quality == 0 ? 1080 : quality)
            await coordinator.enqueue(url: url, title: nil, formatArgs: preset.ytdlpArgs())
            await refresh()
            CopyHUD.show("Added to Downloads", symbol: "arrow.down.circle.fill")
            return
        }
        presentedPicker = .format(url: url, metadata: meta)
    }

    private func coordinatorCookieArgs() -> ([String], Bool) {
        // Reuse coordinator cookie path via a lightweight duplicate of cookie import
        let cookieFile = AppGroup.containerURL()
            .appendingPathComponent("cookies", isDirectory: true)
            .appendingPathComponent("downloader-cookies.txt")
        do {
            try FileManager.default.createDirectory(
                at: cookieFile.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let result = try CookieImporter.combinedCookiesFile(at: cookieFile)
            return (["--cookies", cookieFile.path], result.hadErrors)
        } catch {
            return ([], true)
        }
    }

    private func cookieFileURL(from cookieArgsList: [String]) -> URL? {
        guard let idx = cookieArgsList.firstIndex(of: "--cookies"),
              cookieArgsList.indices.contains(idx + 1) else { return nil }
        return URL(fileURLWithPath: cookieArgsList[idx + 1])
    }

    func add(url: String) async {
        await routeURL(url)
    }

    func refresh() async {
        let ids = (try? coordinator.store.list()) ?? []
        rows = ids.compactMap { try? coordinator.store.fetch(id: $0) }
    }

    func pauseCollection(id: String) async {
        await coordinator.pauseCollection(id: id)
        await refresh()
    }

    func resumeCollection(id: String) async {
        await coordinator.resumeCollection(id: id)
        await refresh()
        CopyHUD.show("Resumed collection", symbol: "play.circle.fill")
    }

    func deleteCollection(id: String, deleteFiles: Bool) async {
        await coordinator.deleteCollection(id: id, deleteFiles: deleteFiles)
        await refresh()
        CopyHUD.show(deleteFiles ? "Deleted collection and files" : "Removed collection", symbol: "trash.fill")
    }

    func resumeInterruptedDownloads() async {
        let paused = rows.filter { $0.state == .paused }
        for record in paused {
            await coordinator.resumeDownload(id: record.id)
        }
        interruptedRecoveryCount = 0
        await refresh()
    }

    func retry(record: DownloadRecord) async {
        await coordinator.reenqueue(record: record)
        await refresh()
        CopyHUD.show("Retrying", symbol: "arrow.clockwise.circle.fill")
    }

    func retryFailed(in records: [DownloadRecord]) async {
        let failedRecords = records.filter { $0.state == .failed }
        guard !failedRecords.isEmpty else { return }
        for record in failedRecords {
            await coordinator.reenqueue(record: record)
        }
        await refresh()
        let message = failedRecords.count == 1 ? "Retrying" : "Retrying \(failedRecords.count)"
        CopyHUD.show(message, symbol: "arrow.clockwise.circle.fill")
    }

    func cancel(id: RecordID) async {
        liveProgress.removeValue(forKey: id.rawValue)
        liveStatus.removeValue(forKey: id.rawValue)
        speedSamples.removeValue(forKey: id.rawValue)
        lastDisplayUpdate.removeValue(forKey: id.rawValue)
        liveDestination.removeValue(forKey: id.rawValue)
        await coordinator.cancelDownload(id: id)
        await refresh()
    }

    func pause(id: RecordID) async {
        liveProgress.removeValue(forKey: id.rawValue)
        liveStatus.removeValue(forKey: id.rawValue)
        speedSamples.removeValue(forKey: id.rawValue)
        lastDisplayUpdate.removeValue(forKey: id.rawValue)
        await coordinator.pauseDownload(id: id)
        await refresh()
        CopyHUD.show("Paused", symbol: "pause.circle.fill")
    }

    func resume(id: RecordID) async {
        await coordinator.resumeDownload(id: id)
        await refresh()
        CopyHUD.show("Resumed", symbol: "play.circle.fill")
    }

    func delete(ids: [RecordID]) async {
        selectedIDs.subtract(ids.map(\.rawValue))
        for id in ids {
            // Capture the actual on-disk path before clearing state
            let actualPath = liveDestination[id.rawValue]
            liveProgress.removeValue(forKey: id.rawValue)
            liveStatus.removeValue(forKey: id.rawValue)
            speedSamples.removeValue(forKey: id.rawValue)
            lastDisplayUpdate.removeValue(forKey: id.rawValue)
            liveDestination.removeValue(forKey: id.rawValue)
            await coordinator.deleteDownload(id: id)
            // Remove the partial file yt-dlp may have left on disk
            if let path = actualPath {
                try? FileManager.default.removeItem(atPath: path)
                try? FileManager.default.removeItem(atPath: path + ".part")
                try? FileManager.default.removeItem(atPath: path + ".ytdl")
            }
        }
        await refresh()
        let msg = ids.count == 1 ? "Deleted" : "Deleted \(ids.count)"
        CopyHUD.show(msg, symbol: "trash.fill")
    }
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
    var onCookieWarning: (() -> Void)?
    var onInterruptedRecovery: ((Int) -> Void)?

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
            self?.onProgress?(id, progress)
        }
        observe(.downloadPhase) { [weak self] note in
            guard let id = note.userInfo?["id"] as? String,
                  let phase = note.userInfo?["phase"] as? String
            else { return }
            self?.onPhase?(id, phase)
        }
        observe(.downloadStateChanged) { [weak self] note in
            guard let id = note.userInfo?["id"] as? String else { return }
            self?.onStateChanged?(id, note.userInfo?["state"] as? String)
        }
        observe(.downloadDestinationPath) { [weak self] note in
            guard let id = note.userInfo?["id"] as? String,
                  let path = note.userInfo?["path"] as? String
            else { return }
            self?.onDestinationPath?(id, path)
        }
        observe(.cookieWarning) { [weak self] _ in
            self?.onCookieWarning?()
        }
        observe(.downloadInterruptedRecovery) { [weak self] note in
            let count = note.userInfo?["count"] as? Int ?? 0
            self?.onInterruptedRecovery?(count)
        }
    }

    private func observe(_ name: Notification.Name, handler: @escaping (Notification) -> Void) {
        let token = NotificationCenter.default.addObserver(
            forName: name, object: nil, queue: .main, using: handler
        )
        tokens.append(token)
    }
}
