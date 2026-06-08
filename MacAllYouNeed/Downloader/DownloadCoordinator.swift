import Core
import Foundation
import Platform

@MainActor
final class DownloadCheckpointThrottler {
    private let interval: TimeInterval
    private let store: DownloadStore
    private var lastWrite: [RecordID: Date] = [:]

    init(interval: TimeInterval = 5, store: DownloadStore) {
        self.interval = interval
        self.store = store
    }

    func record(id: RecordID, progress: DownloadProgress) {
        guard let downloaded = progress.downloadedBytes else { return }
        let now = Date()
        guard now.timeIntervalSince(lastWrite[id] ?? .distantPast) >= interval else { return }
        lastWrite[id] = now
        try? store.updateProgress(id: id, bytesDownloaded: downloaded, bytesTotal: progress.totalBytes)
    }
}

@MainActor
final class DownloadCoordinator {
    let store: DownloadStore
    let queue: DownloadQueue
    let binaries: any BinaryLocator
    var dispatch: DispatchServer?
    private var destinationObserver: NSObjectProtocol?
    private var metadataFetchTasks: [RecordID: Task<Void, Never>] = [:]
    private let log = Logging.logger(for: "downloader", category: "coordinator")

    init(binaries: any BinaryLocator) throws {
        let key = try KeyManager(keychain: SystemKeychain()).deviceKey()
        let dbURL = AppGroup.containerURL().appendingPathComponent("databases/downloads.sqlite")
        let db = try Database(url: dbURL, migrations: DownloadStore.migrations)
        store = try DownloadStore(database: db, deviceKey: key)
        self.binaries = binaries
        let checkpoints = DownloadCheckpointThrottler(store: store)
        let storeRef = store
        queue = DownloadQueue(
            maxConcurrent: 3,
            started: { id in
                Task { @MainActor in
                    try? storeRef.updateState(id: id, to: .running)
                    Self.postStateChanged(id: id, state: .running)
                }
            },
            progress: { id, p in
                NotificationCenter.default.post(
                    name: .downloadProgress, object: nil,
                    userInfo: ["id": id.rawValue, "progress": p]
                )
                Task { @MainActor in checkpoints.record(id: id, progress: p) }
            },
            completion: { id, result in
                Task { @MainActor in
                    switch result {
                    case .success:
                        try? storeRef.updateState(id: id, to: .completed)
                        Self.postStateChanged(id: id, state: .completed)
                        CopyHUD.show("Download finished", symbol: "checkmark.circle.fill")
                    case .failure(let error):
                        recordDownloadFailure(store: storeRef, id: id, error: error)
                        Self.postStateChanged(id: id, state: .failed)
                    }
                }
            }
        )
        destinationObserver = NotificationCenter.default.addObserver(
            forName: .downloadDestinationPath,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let idRaw = note.userInfo?["id"] as? String,
                  let id = RecordID(rawValue: idRaw),
                  let path = note.userInfo?["path"] as? String else { return }
            Task { @MainActor in
                self?.applyDestinationMetadataFallback(id: id, destinationPath: path)
            }
        }
    }

    deinit {
        if let destinationObserver {
            NotificationCenter.default.removeObserver(destinationObserver)
        }
    }

    private static func postStateChanged(id: RecordID, state: DownloadState) {
        NotificationCenter.default.post(
            name: .downloadStateChanged, object: nil,
            userInfo: ["id": id.rawValue, "state": state.rawValue]
        )
    }

    private func cookieArgs() -> ([String], hadErrors: Bool) {
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

    private func postCookieWarningIfNeeded(hadErrors: Bool) {
        guard hadErrors else { return }
        NotificationCenter.default.post(name: .cookieWarning, object: nil)
    }

    func startDispatchServer() async {
        let tokenURL = AppGroup.containerURL().appendingPathComponent("dispatch.token")
        let token = (try? DispatchToken.rotate(at: tokenURL)) ?? UUID().uuidString
        do {
            let server = try DispatchServer(port: 18765, token: token) { [weak self] req in
                await self?.enqueue(url: req.url, title: req.title)
            }
            try await server.start()
            dispatch = server
        } catch {
            log.warning("Could not start DispatchServer: \(error.localizedDescription)")
        }
    }

    /// Re-enqueue an existing record without creating a new DB entry.
    func reenqueue(record: DownloadRecord) async {
        do {
            try store.updateState(id: record.id, to: .queued)
            let dest = URL(fileURLWithPath: record.destinationPath)
            let (cookies, cookieHadErrors) = cookieArgs()
            postCookieWarningIfNeeded(hadErrors: cookieHadErrors)
            let job = try DownloadJob(
                recordID: record.id, url: record.url, destination: dest,
                ytdlp: binaries.ytdlpPath(), ffmpeg: binaries.ffmpegPath(),
                extraArgs: cookies
            )
            await queue.enqueue(job)
        } catch {
            log.error("reenqueue failed: \(error.localizedDescription)")
        }
    }

    func cancelDownload(id: RecordID) async {
        cancelMetadataFetch(for: id)
        await queue.cancel(id)
        try? store.updateState(id: id, to: .failed)
        Self.postStateChanged(id: id, state: .failed)
    }

    func deleteDownload(id: RecordID) async {
        cancelMetadataFetch(for: id)
        await queue.cancel(id)
        try? store.delete(id: id)
        Self.postStateChanged(id: id, state: .failed)
    }

    func pauseDownload(id: RecordID) async {
        await queue.pauseForResume(id) // terminates without firing failure completion
        try? store.updateState(id: id, to: .paused)
        Self.postStateChanged(id: id, state: .paused)
    }

    func resumeDownload(id: RecordID) async {
        do {
            let record = try store.fetch(id: id)
            let dest = URL(fileURLWithPath: record.destinationPath)
            try store.updateState(id: id, to: .queued)
            let (cookies, cookieHadErrors) = cookieArgs()
            postCookieWarningIfNeeded(hadErrors: cookieHadErrors)
            let job = try DownloadJob(
                recordID: record.id, url: record.url, destination: dest,
                ytdlp: binaries.ytdlpPath(), ffmpeg: binaries.ffmpegPath(),
                extraArgs: cookies // --continue already in DownloadJob base args
            )
            await queue.enqueue(job)
            Self.postStateChanged(id: id, state: .running)
        } catch {
            log.error("resumeDownload failed: \(error.localizedDescription)")
        }
    }

    func enqueue(url: String, title: String?) async {
        do {
            let dest = try makeDestinationURL(for: url)
            var record = DownloadRecord(url: url, title: title ?? url, destinationPath: dest.path, state: .queued)
            record = DownloadMetadataFallback.applyingFallbacks(to: record, destinationPath: nil)
            try store.insert(record)
            // Fire-and-forget: fetch metadata first, then start the download.
            // The record is visible in the list immediately with a "Fetching info…" phase.
            let task = Task { [weak self] in
                guard let self else { return }
                await self.fetchMetadataThenStart(record: record, url: url, dest: dest)
            }
            metadataFetchTasks[record.id] = task
        } catch {
            log.error("enqueue failed: \(error.localizedDescription)")
        }
    }

    private func applyDestinationMetadataFallback(id: RecordID, destinationPath: String) {
        do {
            let record = try store.fetch(id: id)
            let updated = DownloadMetadataFallback.applyingFallbacks(to: record, destinationPath: destinationPath)
            guard updated != record else { return }
            try store.update(updated)
            Self.postStateChanged(id: id, state: updated.state)
        } catch {
            log.warning("destination metadata fallback failed: \(error.localizedDescription)")
        }
    }

    private func cancelMetadataFetch(for id: RecordID) {
        metadataFetchTasks[id]?.cancel()
        metadataFetchTasks.removeValue(forKey: id)
    }

    private func shouldStillEnqueue(recordID: RecordID) -> Bool {
        guard let record = try? store.fetch(id: recordID) else { return false }
        return record.state == .queued
    }

    private func fetchMetadataThenStart(record: DownloadRecord, url: String, dest: URL) async {
        defer { metadataFetchTasks.removeValue(forKey: record.id) }
        guard !Task.isCancelled else { return }

        // Signal that we're fetching info before the download starts
        NotificationCenter.default.post(
            name: .downloadPhase, object: nil,
            userInfo: ["id": record.id.rawValue, "phase": "Fetching info…"]
        )

        // Prepare cookies (also writes the cookie file so metadata fetch can use it)
        let (cookieArgsList, cookieHadErrors) = cookieArgs()
        postCookieWarningIfNeeded(hadErrors: cookieHadErrors)

        // Extract cookie file path from the cookie args (["--cookies", "/path/..."]) if present
        let cookieFileURL: URL? = {
            guard let idx = cookieArgsList.firstIndex(of: "--cookies"),
                  cookieArgsList.indices.contains(idx + 1) else { return nil }
            return URL(fileURLWithPath: cookieArgsList[idx + 1])
        }()

        // Fetch title, channel, duration, thumbnail — before starting the download
        if let ytdlpPath = try? binaries.ytdlpPath(),
           let meta = await MetadataFetcher.fetch(url: url, ytdlp: ytdlpPath, cookieFile: cookieFileURL)
        {
            var updated = record
            updated.videoTitle = meta.title
            updated.channelName = meta.channelName
            updated.durationSeconds = meta.durationSeconds
            updated.thumbnailURL = meta.thumbnailURL
            updated.modified = Date()
            try? store.update(updated)
            Self.postStateChanged(id: record.id, state: .queued)
        }

        guard !Task.isCancelled, shouldStillEnqueue(recordID: record.id) else { return }

        // Now start the actual download
        do {
            let ytdlp = try binaries.ytdlpPath()
            let ffmpeg = try binaries.ffmpegPath()
            let job = DownloadJob(
                recordID: record.id, url: url, destination: dest,
                ytdlp: ytdlp, ffmpeg: ffmpeg,
                extraArgs: cookieArgsList
            )
            await queue.enqueue(job)
        } catch {
            log.error("enqueue start failed: \(error.localizedDescription)")
            try? store.updateState(id: record.id, to: .failed)
            Self.postStateChanged(id: record.id, state: .failed)
        }
    }

    private func makeDestinationURL(for url: String) throws -> URL {
        let configured = AppGroupSettings.defaults.string(forKey: "downloadDirectory") ?? ""
        let outputDir: URL = {
            if !configured.isEmpty {
                return URL(fileURLWithPath: configured)
            }
            let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: "/tmp")
            return downloads.appendingPathComponent("MacAllYouNeed", isDirectory: true)
        }()
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        let template = AppGroupSettings.defaults.string(forKey: "downloadOutputTemplate")
            ?? "%(title)s - %(uploader)s.%(ext)s"
        return URL(fileURLWithPath: outputDir.path + "/" + template)
    }

    func prepareInterruptedDownloadsForRetry() async {
        do {
            let ids = try store.list(state: .running) + store.list(state: .queued) + store.list(state: .paused)
            for id in ids {
                try? store.updateState(id: id, to: .failed)
            }
            // Single batch notification instead of N individual ones
            if !ids.isEmpty {
                NotificationCenter.default.post(
                    name: .downloadStateChanged,
                    object: nil,
                    userInfo: ["id": "", "state": "failed"]
                )
            }
        } catch {
            log.error("recovery preparation failed: \(error.localizedDescription)")
        }
    }
}

public extension Notification.Name {
    static let downloadProgress = Notification.Name("downloadProgress")
    static let downloadStateChanged = Notification.Name("downloadStateChanged")
    static let downloadPhase = Notification.Name("downloadPhase")
    static let downloadDestinationPath = Notification.Name("downloadDestinationPath")
    static let cookieWarning = Notification.Name("cookieWarning")
    static let downloaderUpdateRequested = Notification.Name("downloaderUpdateRequested")
}

/// Mark the record as failed, persisting the yt-dlp error message when one is
/// attached. User-initiated cancellations get the bare state update so we don't
/// surface a misleading `Cocoa error 3072` string in the UI.
@MainActor
private func recordDownloadFailure(store: DownloadStore, id: RecordID, error: Error) {
    let nsError = error as NSError
    let isUserCancelled = nsError.domain == NSCocoaErrorDomain
        && nsError.code == CocoaError.userCancelled.rawValue
    let reason = nsError.userInfo[NSLocalizedDescriptionKey] as? String
    if !isUserCancelled, let reason, !reason.isEmpty,
       var record = try? store.fetch(id: id)
    {
        record.lastError = reason
        record.state = .failed
        record.modified = Date()
        try? store.update(record)
    } else {
        try? store.updateState(id: id, to: .failed)
    }
}

enum DownloadMetadataFallback {
    static func applyingFallbacks(to record: DownloadRecord, destinationPath: String?) -> DownloadRecord {
        var updated = record
        if updated.videoTitle?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true,
           let title = destinationPath.flatMap(title(fromDestinationPath:))
        {
            updated.videoTitle = title
        }
        if updated.thumbnailURL?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true,
           let thumbnail = thumbnailURL(for: updated.url)
        {
            updated.thumbnailURL = thumbnail
        }
        if updated != record {
            updated.modified = Date()
        }
        return updated
    }

    static func title(fromDestinationPath path: String) -> String? {
        let title = URL(fileURLWithPath: path)
            .deletingPathExtension()
            .lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : title
    }

    static func thumbnailURL(for url: String) -> String? {
        guard let videoID = youtubeVideoID(from: url) else { return nil }
        return "https://i.ytimg.com/vi/\(videoID)/hqdefault.jpg"
    }

    private static func youtubeVideoID(from rawURL: String) -> String? {
        guard let components = URLComponents(string: rawURL),
              let host = components.host?.lowercased() else { return nil }

        if host == "youtu.be" {
            return components.path
                .split(separator: "/")
                .first
                .map(String.init)
        }

        guard host == "youtube.com" || host.hasSuffix(".youtube.com") else { return nil }
        if let id = components.queryItems?.first(where: { $0.name == "v" })?.value,
           !id.isEmpty
        {
            return id
        }

        let parts = components.path.split(separator: "/").map(String.init)
        if let markerIndex = parts.firstIndex(where: { $0 == "shorts" || $0 == "embed" }),
           parts.indices.contains(markerIndex + 1)
        {
            return parts[markerIndex + 1]
        }

        return nil
    }
}
