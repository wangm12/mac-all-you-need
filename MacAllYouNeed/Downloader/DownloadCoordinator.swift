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
    private var periodicCookieSyncTask: Task<Void, Never>?
    private let log = Logging.logger(for: "downloader", category: "coordinator")
    private let extensionCookieSyncIntervalNanos: UInt64 = 30 * 60 * 1_000_000_000

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
        periodicCookieSyncTask?.cancel()
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
        let extensionCookieFile = AppGroup.containerURL()
            .appendingPathComponent("cookies", isDirectory: true)
            .appendingPathComponent("downloader-extension-cookies.txt")
        let cookieMode = AppGroupSettings.defaults.string(forKey: "downloadCookieMode") ?? "browser_auto"
        do {
            try FileManager.default.createDirectory(
                at: cookieFile.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if cookieMode == "extension_only" {
                let exists = FileManager.default.fileExists(atPath: extensionCookieFile.path)
                return (exists ? ["--cookies", extensionCookieFile.path] : [], !exists)
            }
            let browserPref = AppGroupSettings.defaults.string(forKey: "downloadCookieBrowserProfile") ?? "chrome"
            let preferredBrowser = preferredBrowserProfile(for: browserPref)
            let options = CookieImportOptions(
                preferredBrowser: preferredBrowser,
                includeSafari: preferredBrowser == nil || preferredBrowser == .safari,
                appendExistingCookieFile: extensionCookieFile
            )
            let result = try CookieImporter.combinedCookiesFile(at: cookieFile, options: options)
            return (["--cookies", cookieFile.path], result.hadErrors)
        } catch {
            return ([], true)
        }
    }

    private func preferredBrowserProfile(for raw: String) -> BrowserProfile.Browser? {
        switch raw {
        case "chrome", "chromium":
            .chrome
        case "edge":
            .edge
        case "brave":
            .brave
        case "safari":
            .safari
        default:
            nil
        }
    }

    private func postCookieWarningIfNeeded(hadErrors: Bool) {
        guard hadErrors else { return }
        let cookieMode = AppGroupSettings.defaults.string(forKey: "downloadCookieMode") ?? "browser_auto"
        let message: String
        if cookieMode == "extension_only" {
            message = "Mac All You Need Companion mode is selected but synced cookies are missing. Install Companion and sync cookies in Downloads settings, or switch to Browser Auto."
        } else {
            message = "Some browser profiles could not be imported. Downloads requiring login may fail."
        }
        NotificationCenter.default.post(name: .cookieWarning, object: nil, userInfo: ["message": message])
    }

    func startDispatchServer() async {
        guard dispatch == nil else { return }
        let tokenURL = AppGroup.containerURL().appendingPathComponent("dispatch.token")
        let token = (try? DispatchToken.rotate(at: tokenURL)) ?? UUID().uuidString
        do {
            let server = try DispatchServer(port: 18765, token: token) { req in
                await self.handleDispatchRequest(req)
            }
            try await server.start()
            dispatch = server
            startPeriodicExtensionCookieSync()
        } catch {
            log.warning("Could not start DispatchServer: \(error.localizedDescription)")
        }
    }

    func stopDispatchServer() async {
        periodicCookieSyncTask?.cancel()
        periodicCookieSyncTask = nil
        if let server = dispatch {
            await server.stop()
            dispatch = nil
        }
    }

    private func startPeriodicExtensionCookieSync() {
        periodicCookieSyncTask?.cancel()
        periodicCookieSyncTask = Task { [weak self] in
            guard let self else { return }
            await self.requestExtensionCookieSyncIfNeeded()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: self.extensionCookieSyncIntervalNanos)
                if Task.isCancelled { break }
                await self.requestExtensionCookieSyncIfNeeded()
            }
        }
    }

    private func requestExtensionCookieSyncIfNeeded() async {
        let mode = AppGroupSettings.defaults.string(forKey: "downloadCookieMode")
            ?? UserDefaults.standard.string(forKey: "downloadCookieMode")
            ?? "browser_auto"
        guard mode == "extension_only" else { return }
        await dispatch?.requestCookieSync()
    }

    private func handleDispatchRequest(_ req: DispatchServer.Request) async {
        guard let route = DownloadURLClassifier.route(for: req.url) else { return }
        switch route {
        case let .single(url):
            if shouldBlockForMissingExtensionCookies(url: url) {
                NotificationCenter.default.post(
                    name: .cookieWarning,
                    object: nil,
                    userInfo: [
                        "message": "Mac All You Need Companion mode is selected but synced cookies are missing. Install Companion and sync cookies in Downloads settings, or switch to Browser Auto."
                    ]
                )
                return
            }
            let quality = AppGroupSettings.defaults.integer(forKey: "downloadDefaultVideoQuality")
            let preset = DownloadFormatPreset.fromDefaultQualitySetting(quality == 0 ? 1080 : quality)
            await enqueue(
                url: url,
                title: req.title,
                formatArgs: preset.ytdlpArgs(),
                mediaType: req.mediaType,
                referer: req.referer,
                customHeaders: req.headers
            )
        case .collection, .douyinProfile, .multiURL:
            await MainActor.run {
                NotificationCenter.default.post(
                    name: .downloadRouteRequested,
                    object: nil,
                    userInfo: [
                        "url": req.url,
                        "title": req.title as Any,
                        "type": req.mediaType as Any,
                        "referer": req.referer as Any,
                        "headers": req.headers as Any
                    ]
                )
            }
        }
    }

    private func shouldBlockForMissingExtensionCookies(url: String) -> Bool {
        let cookieMode = AppGroupSettings.defaults.string(forKey: "downloadCookieMode")
            ?? UserDefaults.standard.string(forKey: "downloadCookieMode")
            ?? "browser_auto"
        let extensionCookieFile = AppGroup.containerURL()
            .appendingPathComponent("cookies", isDirectory: true)
            .appendingPathComponent("downloader-extension-cookies.txt")
        let hasExtensionCookieFile = FileManager.default.fileExists(atPath: extensionCookieFile.path)
        return Self.dispatchShouldBlockForMissingExtensionCookies(
            url: url,
            cookieMode: cookieMode,
            hasExtensionCookieFile: hasExtensionCookieFile
        )
    }

    static func dispatchShouldBlockForMissingExtensionCookies(
        url: String,
        cookieMode: String,
        hasExtensionCookieFile: Bool
    ) -> Bool {
        guard cookieMode == "extension_only" else { return false }
        guard urlNeedsAuthCookies(url) else { return false }
        return !hasExtensionCookieFile
    }

    private static func urlNeedsAuthCookies(_ rawURL: String) -> Bool {
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

    /// Re-enqueue an existing record without creating a new DB entry.
    func reenqueue(record: DownloadRecord) async {
        do {
            try store.updateState(id: record.id, to: .queued)
            try await startJob(for: record)
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
            try store.updateState(id: id, to: .queued)
            try await startJob(for: record)
            Self.postStateChanged(id: id, state: .running)
        } catch {
            log.error("resumeDownload failed: \(error.localizedDescription)")
        }
    }

    func listCollectionEntries(url: String) async throws -> PlaylistListResult {
        let (cookieArgsList, _) = cookieArgs()
        let cookieFileURL: URL? = cookieFileURL(from: cookieArgsList)
        guard let ytdlpPath = try? binaries.ytdlpPath() else {
            throw PlaylistListError.ytdlpFailed(code: -1, message: "yt-dlp not available")
        }
        return try await PlaylistEntryLister.list(url: url, ytdlp: ytdlpPath, cookieFile: cookieFileURL)
    }

    func enqueueBulk(
        entries: [BulkEnqueueEntry],
        collectionTitle: String,
        kind: DownloadCollectionKind,
        formatArgs: [String] = []
    ) async throws {
        guard !entries.isEmpty else { return }
        guard entries.count <= PlaylistEntryLister.maxBulkItems else {
            throw PlaylistListError.tooManyItems(count: entries.count)
        }

        let collectionID = UUID().uuidString
        let useSubfolder = AppGroupSettings.defaults.object(forKey: "downloadCollectionSubfolder") as? Bool ?? true
        let dest = try DownloadDestinationBuilder.destinationURL(
            collectionTitle: collectionTitle,
            useCollectionSubfolder: useSubfolder
        )

        var records: [DownloadRecord] = []
        for (index, entry) in entries.enumerated() {
            let pageURL = entry.pageURL.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !pageURL.isEmpty else { continue }
            var record = DownloadRecord(
                url: pageURL,
                title: entry.title,
                destinationPath: dest.path,
                state: .queued
            )
            record.pageURL = pageURL
            record.collectionID = collectionID
            record.collectionIndex = entry.playlistIndex ?? (index + 1)
            record.collectionTitle = collectionTitle
            record.collectionKind = kind
            record.videoTitle = entry.title
            record.channelName = entry.channel.isEmpty ? nil : entry.channel
            record.durationSeconds = entry.durationSeconds
            record.thumbnailURL = entry.thumbnailURL
            record = DownloadMetadataFallback.applyingFallbacks(to: record, destinationPath: nil)
            records.append(record)
        }

        guard !records.isEmpty else { return }
        _ = try store.insertBulk(records)
        Self.postBulkStateChanged(count: records.count)

        let sleepSeconds = DownloadBatchRateLimiter.effectiveSleepSeconds(kind: kind, count: records.count)
        for (index, record) in records.enumerated() {
            let stagger = Double(index) * sleepSeconds
            let task = Task { [weak self] in
                guard let self else { return }
                if stagger > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(stagger * 1_000_000_000))
                }
                await self.fetchMetadataThenStart(
                    record: record,
                    url: record.url,
                    dest: dest,
                    formatArgs: formatArgs
                )
            }
            metadataFetchTasks[record.id] = task
        }
    }

    func enqueue(
        url: String,
        title: String?,
        formatArgs: [String] = [],
        mediaType: String? = nil,
        referer: String? = nil,
        customHeaders: [String: String]? = nil
    ) async {
        do {
            let dest = try makeDestinationURL(for: nil)
            var record = DownloadRecord(url: url, title: title ?? url, destinationPath: dest.path, state: .queued)
            record.pageURL = url
            record.mediaType = mediaType?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            record.referer = referer?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            record.customHeaders = (customHeaders?.isEmpty == false) ? customHeaders : nil
            record = DownloadMetadataFallback.applyingFallbacks(to: record, destinationPath: nil)
            try store.insert(record)
            let task = Task { [weak self] in
                guard let self else { return }
                await self.fetchMetadataThenStart(record: record, url: url, dest: dest, formatArgs: formatArgs)
            }
            metadataFetchTasks[record.id] = task
        } catch {
            log.error("enqueue failed: \(error.localizedDescription)")
        }
    }

    func pauseCollection(id: String) async {
        guard let records = try? store.records(inCollection: id) else { return }
        for record in records where [.running, .queued].contains(record.state) {
            await pauseDownload(id: record.id)
        }
    }

    func resumeCollection(id: String) async {
        guard let records = try? store.records(inCollection: id) else { return }
        for record in records where record.state == .paused || record.state == .failed {
            await reenqueue(record: record)
        }
    }

    func deleteCollection(id: String, deleteFiles: Bool) async {
        guard let records = try? store.records(inCollection: id) else { return }
        for record in records {
            if deleteFiles {
                await deleteDownloadWithFiles(record: record)
            } else {
                await deleteDownload(id: record.id)
            }
        }
    }

    private func deleteDownloadWithFiles(record: DownloadRecord) async {
        let path = record.destinationPath
        await deleteDownload(id: record.id)
        guard !path.isEmpty else { return }
        try? FileManager.default.removeItem(atPath: path)
        try? FileManager.default.removeItem(atPath: path + ".part")
        try? FileManager.default.removeItem(atPath: path + ".ytdl")
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

    private func fetchMetadataThenStart(
        record: DownloadRecord,
        url: String,
        dest: URL,
        formatArgs: [String] = []
    ) async {
        defer { metadataFetchTasks.removeValue(forKey: record.id) }
        guard !Task.isCancelled else { return }

        NotificationCenter.default.post(
            name: .downloadPhase, object: nil,
            userInfo: ["id": record.id.rawValue, "phase": "Fetching info…"]
        )

        let (cookieArgsList, cookieHadErrors) = cookieArgs()
        postCookieWarningIfNeeded(hadErrors: cookieHadErrors)
        let cookieFileURL = cookieFileURL(from: cookieArgsList)
        let selectedEngine = DownloadEngineRouter.selectEngine(for: record)
        let shouldFetchMetadata = selectedEngine != .ffmpegDirect

        if shouldFetchMetadata,
           record.videoTitle?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true,
           let ytdlpPath = try? binaries.ytdlpPath(),
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

        do {
            let latest = try store.fetch(id: record.id)
            try await startJob(for: latest, formatArgs: formatArgs)
        } catch {
            log.error("enqueue start failed: \(error.localizedDescription)")
            try? store.updateState(id: record.id, to: .failed)
            Self.postStateChanged(id: record.id, state: .failed)
        }
    }

    private func startJob(for record: DownloadRecord, formatArgs: [String] = []) async throws {
        let dest = URL(fileURLWithPath: record.destinationPath)
        let (cookies, cookieHadErrors) = cookieArgs()
        postCookieWarningIfNeeded(hadErrors: cookieHadErrors)
        let selectedEngine = DownloadEngineRouter.selectEngine(for: record)
        NotificationCenter.default.post(
            name: .downloadPhase,
            object: nil,
            userInfo: ["id": record.id.rawValue, "phase": "\(selectedEngine.rawValue)…"]
        )
        var batchArgs: [String] = []
        if let kind = record.collectionKind, let collectionID = record.collectionID, !collectionID.isEmpty {
            let batchCount = (try? store.records(inCollection: collectionID).count) ?? 1
            batchArgs = DownloadBatchRateLimiter.gentleSleepRequestsArgs(kind: kind, batchCount: batchCount)
        }
        let job: DownloadJob
        switch selectedEngine {
        case .ytdlp:
            job = try makeYtDlpJob(
                record: record,
                destination: dest,
                cookies: cookies,
                formatArgs: formatArgs,
                batchArgs: batchArgs
            )
        case .douyinDirect:
            job = try makeYtDlpJob(
                record: record,
                destination: dest,
                cookies: cookies,
                formatArgs: formatArgs,
                batchArgs: batchArgs + ["--no-playlist"]
            )
        case .ffmpegDirect:
            job = try makeFfmpegDirectJob(record: record, destination: dest)
        }
        await queue.enqueue(job)
    }

    private func makeYtDlpJob(
        record: DownloadRecord,
        destination: URL,
        cookies: [String],
        formatArgs: [String],
        batchArgs: [String]
    ) throws -> DownloadJob {
        let extraArgs = YtDlpArgumentBuilder.build(
            record: record,
            cookies: cookies,
            formatArgs: formatArgs,
            batchArgs: batchArgs,
            options: ytdlpArgumentOptions()
        )
        return try DownloadJob(
            recordID: record.id,
            url: record.url,
            destination: destination,
            ytdlp: binaries.ytdlpPath(),
            ffmpeg: binaries.ffmpegPath(),
            extraArgs: extraArgs,
            collectionID: record.collectionID,
            collectionIndex: record.collectionIndex,
            enqueuedAt: record.created
        )
    }

    private func makeFfmpegDirectJob(record: DownloadRecord, destination: URL) throws -> DownloadJob {
        var args = ["-y"]
        if let referer = record.referer?.trimmingCharacters(in: .whitespacesAndNewlines), !referer.isEmpty {
            args += ["-referer", referer]
        }
        if let headers = record.customHeaders, !headers.isEmpty {
            let joined = headers
                .keys
                .sorted()
                .compactMap { key -> String? in
                    guard let value = headers[key] else { return nil }
                    let k = key.trimmingCharacters(in: .whitespacesAndNewlines)
                    let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !k.isEmpty, !v.isEmpty else { return nil }
                    return "\(k): \(v)\r\n"
                }
                .joined()
            if !joined.isEmpty {
                args += ["-headers", joined]
            }
        }
        args += ["-i", record.url, "-c", "copy", "-movflags", "+faststart", destination.path]
        return DownloadJob(
            recordID: record.id,
            url: record.url,
            destination: destination,
            executable: try binaries.ffmpegPath(),
            arguments: args,
            collectionID: record.collectionID,
            collectionIndex: record.collectionIndex,
            enqueuedAt: record.created
        )
    }

    private func ytdlpArgumentOptions() -> YtDlpArgumentOptions {
        let defaults = AppGroupSettings.defaults
        let configuredFragments = defaults.integer(forKey: "downloadConcurrentFragments")
        let concurrentFragments = configuredFragments > 0 ? configuredFragments : 4
        let sleepInterval = max(0, defaults.double(forKey: "downloadSleepInterval"))
        let rawSpeedMode = defaults.string(forKey: "downloadSpeedMode") ?? DownloadSpeedMode.balanced.rawValue
        let speedMode = DownloadSpeedMode(rawValue: rawSpeedMode) ?? .balanced
        let external = defaults.string(forKey: "downloadExternalDownloader")
        return YtDlpArgumentOptions(
            concurrentFragments: concurrentFragments,
            sleepInterval: sleepInterval,
            speedMode: speedMode,
            externalDownloader: external
        )
    }

    private func cookieFileURL(from cookieArgsList: [String]) -> URL? {
        guard let idx = cookieArgsList.firstIndex(of: "--cookies"),
              cookieArgsList.indices.contains(idx + 1) else { return nil }
        return URL(fileURLWithPath: cookieArgsList[idx + 1])
    }

    private static func postBulkStateChanged(count: Int) {
        NotificationCenter.default.post(
            name: .downloadStateChanged,
            object: nil,
            userInfo: ["id": "", "state": "queued", "bulkAdded": count]
        )
    }

    private func makeDestinationURL(for collectionTitle: String?) throws -> URL {
        let useSubfolder = AppGroupSettings.defaults.object(forKey: "downloadCollectionSubfolder") as? Bool ?? true
        return try DownloadDestinationBuilder.destinationURL(
            collectionTitle: collectionTitle,
            useCollectionSubfolder: useSubfolder && collectionTitle != nil
        )
    }

    func prepareInterruptedDownloadsForRetry() async {
        do {
            let ids = try store.list(state: .running) + store.list(state: .queued)
            for id in ids {
                try? store.updateState(id: id, to: .paused)
            }
            if !ids.isEmpty {
                NotificationCenter.default.post(
                    name: .downloadInterruptedRecovery,
                    object: nil,
                    userInfo: ["count": ids.count]
                )
                NotificationCenter.default.post(
                    name: .downloadStateChanged,
                    object: nil,
                    userInfo: ["id": "", "state": "paused"]
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
    static let downloadInterruptedRecovery = Notification.Name("downloadInterruptedRecovery")
    static let downloadRouteRequested = Notification.Name("downloadRouteRequested")
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
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
