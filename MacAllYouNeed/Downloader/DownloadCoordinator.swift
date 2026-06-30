import Core
import Foundation
import Platform

actor DownloadCheckpointThrottler {
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
    enum BulkEnqueueResult {
        case local(records: [DownloadRecord])
        case forwarded
    }

    let store: DownloadStore
    let queue: DownloadQueue
    let binaries: any BinaryLocator
    var dispatch: DispatchServer?
    private var destinationObserver: NSObjectProtocol?
    private var settingsObserver: NSObjectProtocol?
    private var metadataFetchTasks: [RecordID: Task<Void, Never>] = [:]
    private var periodicCookieSyncTask: Task<Void, Never>?
    private let log = Logging.logger(for: "downloader", category: "coordinator")
    private let extensionCookieSyncIntervalNanos: UInt64 = 30 * 60 * 1_000_000_000
    nonisolated private static let helperRequestTimeout: TimeInterval = 8
    private var isHelperProcess: Bool {
        Bundle.main.bundleIdentifier == "com.macallyouneed.app.downloader"
    }
    private var helperBaseURL: URL? {
        guard !isHelperProcess else { return nil }
        return URL(string: "http://127.0.0.1:18765")
    }

    init(binaries: any BinaryLocator) throws {
        let key = try KeyManager(keychain: SystemKeychain()).deviceKey()
        let dbURL = AppGroup.containerURL().appendingPathComponent("databases/downloads.sqlite")
        let db = try Database(url: dbURL, migrations: DownloadStore.migrations)
        store = try DownloadStore(database: db, deviceKey: key)
        self.binaries = binaries
        let checkpoints = DownloadCheckpointThrottler(store: store)
        let storeRef = store
        queue = DownloadQueue(
            maxConcurrent: Self.currentConcurrency(),
            started: { id in
                Task.detached(priority: .utility) {
                    try? storeRef.updateState(id: id, to: .running)
                    Self.postStateChanged(id: id, state: .running)
                }
            },
            progress: { id, p in
                Self.postCrossProcessNotification(
                    name: .downloadProgress,
                    userInfo: ["id": id.rawValue, "progress": p]
                )
                Task.detached(priority: .utility) {
                    await checkpoints.record(id: id, progress: p)
                }
            },
            completion: { id, result in
                Task.detached(priority: .utility) {
                    switch result {
                    case .success:
                        try? storeRef.updateState(id: id, to: .completed)
                        Self.postStateChanged(id: id, state: .completed)
                    case .failure(let error):
                        recordDownloadFailure(store: storeRef, id: id, error: error)
                        Self.postStateChanged(id: id, state: .failed)
                    }
                }
            }
        )
        destinationObserver = DistributedNotificationCenter.default().addObserver(
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
        settingsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: AppGroupSettings.defaults,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.applyConcurrencySetting() }
        }
        Task { @MainActor [weak self] in await self?.applyConcurrencySetting() }
    }

    deinit {
        if let destinationObserver {
            NotificationCenter.default.removeObserver(destinationObserver)
        }
        if let settingsObserver {
            NotificationCenter.default.removeObserver(settingsObserver)
        }
        periodicCookieSyncTask?.cancel()
    }

    nonisolated private static func postStateChanged(id: RecordID, state: DownloadState) {
        postCrossProcessNotification(
            name: .downloadStateChanged,
            userInfo: ["id": id.rawValue, "state": state.rawValue]
        )
    }

    private static func currentConcurrency() -> Int {
        let raw = AppGroupSettings.defaults.integer(forKey: "downloadConcurrency")
        return max(1, raw)
    }

    private func applyConcurrencySetting() async {
        await queue.setMaxConcurrent(Self.currentConcurrency())
    }

    nonisolated private static func makeCookieArgs() -> ([String], hadErrors: Bool) {
        DownloadCookieConfiguration.makeCookieArgs()
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
        Self.postCrossProcessNotification(name: .cookieWarning, userInfo: ["message": message])
    }

    func startDispatchServer() async {
        guard Bundle.main.bundleIdentifier == "com.macallyouneed.app.downloader" else { return }
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
        guard Bundle.main.bundleIdentifier == "com.macallyouneed.app.downloader" else { return }
        periodicCookieSyncTask?.cancel()
        periodicCookieSyncTask = nil
        if let server = dispatch {
            await server.stop()
            dispatch = nil
        }
    }

    func resetCompanionRegistration() async {
        let tokenURL = AppGroup.containerURL().appendingPathComponent("extension.token")
        try? FileManager.default.removeItem(at: tokenURL)
        await dispatch?.resetExtensionToken()
        guard let url = URL(string: "http://127.0.0.1:18765/companion-reset") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        _ = try? await URLSession.shared.data(for: request)
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
        let normalized = Self.normalizeDouyinExtensionDispatch(
            url: req.url,
            title: req.title,
            mediaType: req.mediaType,
            pageURL: req.pageURL,
            douyinAwemeID: req.douyinAwemeID
        )
        switch req.action {
        case .enqueue:
            guard let route = DownloadURLClassifier.route(for: normalized.url) else { return }
            switch route {
            case let .single(url):
                if shouldBlockForMissingExtensionCookies(url: url) {
                    Self.postCrossProcessNotification(
                        name: .cookieWarning,
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
                    mediaType: normalized.mediaType,
                    referer: req.referer,
                    customHeaders: req.headers,
                    pageURL: normalized.pageURL,
                    douyinAwemeID: normalized.awemeID
                )
            case .collection, .douyinProfile, .multiURL:
                await MainActor.run {
                    Self.postCrossProcessNotification(
                        name: .downloadRouteRequested,
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
        case .retry:
            if let recordID = req.recordID, let id = RecordID(rawValue: recordID), let record = try? store.fetch(id: id) {
                await reenqueue(record: record)
            }
        case .pause:
            if let recordID = req.recordID, let id = RecordID(rawValue: recordID) {
                await pauseDownload(id: id)
            }
        case .resume:
            if let recordID = req.recordID, let id = RecordID(rawValue: recordID) {
                await resumeDownload(id: id)
            }
        case .delete:
            if let recordID = req.recordID, let id = RecordID(rawValue: recordID) {
                if req.deleteFiles {
                    if let record = try? store.fetch(id: id) {
                        await deleteDownloadWithFiles(record: record)
                    }
                } else {
                    await deleteDownload(id: id)
                }
            }
        case .pauseCollection:
            if let collectionID = req.collectionID { await pauseCollection(id: collectionID) }
        case .resumeCollection:
            if let collectionID = req.collectionID { await resumeCollection(id: collectionID) }
        case .deleteCollection:
            if let collectionID = req.collectionID { await deleteCollection(id: collectionID, deleteFiles: req.deleteFiles) }
        case .bulkEnqueue:
            if let entries = req.entries, !entries.isEmpty {
                let title = req.title ?? "Downloads"
                let kind: DownloadCollectionKind = req.mediaType == "douyin" ? .douyinProfile : .multiURL
                _ = try? await enqueueBulk(entries: entries, collectionTitle: title, kind: kind)
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
        if helperBaseURL != nil, await sendAction(.retry, recordID: record.id.rawValue) {
            return
        }
        do {
            try store.updateState(id: record.id, to: .queued)
            // Surface the queued state immediately so the row reflects the retry
            // before the (potentially slow) resolve/startJob work runs.
            Self.postStateChanged(id: record.id, state: .queued)
            try await startJob(for: record)
        } catch {
            log.error("reenqueue failed: \(error.localizedDescription)")
        }
    }

    func cancelDownload(id: RecordID) async {
        if helperBaseURL != nil, await sendAction(.delete, recordID: id.rawValue) {
            return
        }
        cancelMetadataFetch(for: id)
        await queue.cancel(id)
        try? store.updateState(id: id, to: .failed)
        Self.postStateChanged(id: id, state: .failed)
    }

    func deleteDownload(id: RecordID) async {
        if helperBaseURL != nil, await sendAction(.delete, recordID: id.rawValue) {
            return
        }
        cancelMetadataFetch(for: id)
        await queue.cancel(id)
        try? store.delete(id: id)
        NotificationCenter.default.post(
            name: .downloadStateChanged,
            object: nil,
            userInfo: ["id": id.rawValue]
        )
    }

    func deleteDownloads(ids: [RecordID]) async {
        guard !ids.isEmpty else { return }
        if helperBaseURL != nil {
            let helperResults = await withTaskGroup(of: (RecordID, Bool).self) { group in
                for id in ids {
                    group.addTask { [id] in
                        (id, await self.sendAction(.delete, recordID: id.rawValue))
                    }
                }
                var results: [(RecordID, Bool)] = []
                results.reserveCapacity(ids.count)
                for await result in group {
                    results.append(result)
                }
                return results
            }
            let helperSucceeded = Set(helperResults.filter { $0.1 }.map { $0.0 })
            for id in ids where !helperSucceeded.contains(id) {
                cancelMetadataFetch(for: id)
                await queue.cancel(id)
                try? store.delete(id: id)
                NotificationCenter.default.post(
                    name: .downloadStateChanged,
                    object: nil,
                    userInfo: ["id": id.rawValue]
                )
            }
            return
        }
        cancelMetadataFetches(for: ids)
        await queue.cancelMany(ids)
        try? store.delete(ids: ids)
        postDeletedStateChanges(ids)
    }

    func pauseDownload(id: RecordID) async {
        if helperBaseURL != nil, await sendAction(.pause, recordID: id.rawValue) {
            return
        }
        await queue.pauseForResume(id) // terminates without firing failure completion
        try? store.updateState(id: id, to: .paused)
        Self.postStateChanged(id: id, state: .paused)
    }

    func resumeDownload(id: RecordID) async {
        if helperBaseURL != nil, await sendAction(.resume, recordID: id.rawValue) {
            return
        }
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
        let (cookieArgsList, _) = Self.makeCookieArgs()
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
    ) async throws -> BulkEnqueueResult {
        let helperBaseURL = helperBaseURL
        if let helperBaseURL, await Self.sendBulkToHelper(
            helperBaseURL: helperBaseURL,
            entries: entries,
            collectionTitle: collectionTitle
        ) {
            return .forwarded
        }

        let store = store
        let binaries = binaries
        let dispatch = dispatch
        let queue = queue
        let log = log
        let shouldDeferBulkJobBuild = entries.count >= 64

        return await Task.detached(priority: .userInitiated) { [entries, collectionTitle, kind, formatArgs, store, binaries, dispatch, queue, log] in
            let collectionID = UUID().uuidString
            let bulkConfig = Self.prepareBulkConfiguration(collectionTitle: collectionTitle)
            let records: [DownloadRecord] = entries.enumerated().compactMap { index, entry in
                let pageURL = entry.pageURL.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !pageURL.isEmpty else { return nil }
                var record = DownloadRecord(
                    url: pageURL,
                    title: entry.title,
                    destinationPath: bulkConfig.dest.path,
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
                return DownloadMetadataFallback.applyingFallbacks(to: record, destinationPath: nil)
            }
            guard !records.isEmpty else { return .local(records: []) }

            do {
                _ = try store.insertBulk(records)
                Self.postBulkStateChanged(count: records.count)

                if kind == .douyinProfile {
                    await Self.requestDouyinCookieSyncIfPossible(dispatch: dispatch)
                }

                if shouldDeferBulkJobBuild {
                    Task.detached(priority: .userInitiated) {
                        let ytdlpPath = try? binaries.ytdlpPath()
                        let ffmpegPath = try? binaries.ffmpegPath()
                        let jobs = await Self.buildBulkJobs(
                            records: records,
                            totalBulkCount: records.count,
                            bulkConfig: bulkConfig,
                            formatArgs: formatArgs,
                            ytdlpPath: ytdlpPath,
                            ffmpegPath: ffmpegPath,
                            store: store
                        )
                        await queue.enqueueBatch(jobs)
                    }
                    return .local(records: records)
                }

                let ytdlpPath = try? binaries.ytdlpPath()
                let ffmpegPath = try? binaries.ffmpegPath()
                let batchSize = 16
                var pendingJobs: [DownloadJob] = []
                pendingJobs.reserveCapacity(batchSize)

                func flushPendingJobs() async {
                    guard !pendingJobs.isEmpty else { return }
                    await queue.enqueueBatch(pendingJobs)
                    pendingJobs.removeAll(keepingCapacity: true)
                }

                if kind == .douyinProfile {
                    // Resolve incrementally so the first few items can start
                    // quickly, but batch queue mutations to avoid repeated
                    // sort/start churn on large collections.
                    for record in records {
                        if Task.isCancelled { break }
                        guard let job = await Self.buildBulkJob(
                            record: record,
                            totalBulkCount: records.count,
                            bulkConfig: bulkConfig,
                            formatArgs: formatArgs,
                            ytdlpPath: ytdlpPath,
                            ffmpegPath: ffmpegPath,
                            store: store
                        ) else { continue }
                        pendingJobs.append(job)
                        if pendingJobs.count >= batchSize {
                            await flushPendingJobs()
                            await Task.yield()
                        }
                    }
                } else {
                    let jobs = await Self.buildBulkJobs(
                        records: records,
                        totalBulkCount: records.count,
                        bulkConfig: bulkConfig,
                        formatArgs: formatArgs,
                        ytdlpPath: ytdlpPath,
                        ffmpegPath: ffmpegPath,
                        store: store
                    )
                    pendingJobs.append(contentsOf: jobs)
                }

                await flushPendingJobs()
                return .local(records: records)
            } catch {
                log.error("bulk enqueue failed: \(error.localizedDescription)")
                return .local(records: records)
            }
        }.value
    }

    nonisolated private static func buildBulkJobs(
        records: [DownloadRecord],
        totalBulkCount: Int,
        bulkConfig: BulkPreparation,
        formatArgs: [String],
        ytdlpPath: URL?,
        ffmpegPath: URL?,
        store: DownloadStore
    ) async -> [DownloadJob] {
        guard let ytdlpPath, let ffmpegPath else { return [] }
        var jobs: [DownloadJob] = []
        jobs.reserveCapacity(records.count)
        let douyinResolves = await resolveBulkDouyinRecords(records, cookieFile: bulkConfig.cookieFileURL)

        for (index, record) in records.enumerated() {
            if Task.isCancelled { break }
            let job: DownloadJob
            switch DownloadEngineRouter.selectEngine(for: record) {
            case .ytdlp:
                let extraArgs = YtDlpArgumentBuilder.build(
                    record: record,
                    cookies: bulkConfig.cookieArgsList,
                    formatArgs: formatArgs,
                    batchArgs: DownloadBatchRateLimiter.gentleSleepRequestsArgs(
                        kind: record.collectionKind ?? .multiURL,
                        batchCount: totalBulkCount
                    ),
                    options: bulkConfig.ytdlpOptions
                )
                job = DownloadJob(
                    recordID: record.id,
                    url: record.url,
                    destination: URL(fileURLWithPath: record.destinationPath),
                    ytdlp: ytdlpPath,
                    ffmpeg: ffmpegPath,
                    extraArgs: extraArgs,
                    collectionID: record.collectionID,
                    collectionIndex: record.collectionIndex,
                    enqueuedAt: record.created
                )
            case .douyinDirect:
                let resolved = douyinResolves[index]
                var updated = record
                if let resolved {
                    updated.douyinAwemeID = resolved.awemeId
                    updated.videoTitle = resolved.title
                    if updated.channelName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true,
                       !resolved.author.isEmpty
                    {
                        updated.channelName = resolved.author
                    }
                    if updated.thumbnailURL?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true,
                       let thumbnail = resolved.thumbnailURL
                    {
                        updated.thumbnailURL = thumbnail
                    }
                    updated.referer = DouyinAPISupport.origin
                    updated.destinationPath = Self.backgroundConcreteDestination(
                        from: bulkConfig.dest,
                        title: updated.videoTitle,
                        author: updated.channelName,
                        fallbackID: resolved.awemeId,
                        ext: "mp4"
                    ).path
                    try? store.update(updated)
                }
                let target = URL(fileURLWithPath: updated.destinationPath)
                job = DownloadJob(
                    recordID: updated.id,
                    url: resolved?.directURL ?? updated.url,
                    destination: target,
                    executable: ffmpegPath,
                    arguments: {
                        var args = ["-y"]
                        if let referer = updated.referer?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                            ?? (resolved != nil ? DouyinAPISupport.origin : nil)
                        {
                            args += ["-referer", referer]
                        }
                        var headers = updated.customHeaders ?? [:]
                        if let extraHeaders = resolved?.downloadHeaders {
                            for (key, value) in extraHeaders {
                                headers[key] = value
                            }
                        }
                        if !headers.isEmpty {
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
                        args += ["-i", resolved?.directURL ?? updated.url, "-c", "copy", "-movflags", "+faststart", target.path]
                        return args
                    }(),
                    collectionID: updated.collectionID,
                    collectionIndex: updated.collectionIndex,
                    enqueuedAt: updated.created
                )
            case .ffmpegDirect:
                job = DownloadJob(
                    recordID: record.id,
                    url: record.url,
                    destination: URL(fileURLWithPath: record.destinationPath),
                    executable: ffmpegPath,
                    arguments: ["-y", "-i", record.url, "-c", "copy", "-movflags", "+faststart", record.destinationPath],
                    collectionID: record.collectionID,
                    collectionIndex: record.collectionIndex,
                    enqueuedAt: record.created
                )
            }
            jobs.append(job)
            if index.isMultiple(of: 16) {
                await Task.yield()
            }
        }
        return jobs
    }

    nonisolated private static func buildBulkJob(
        record: DownloadRecord,
        totalBulkCount: Int,
        bulkConfig: BulkPreparation,
        formatArgs: [String],
        ytdlpPath: URL?,
        ffmpegPath: URL?,
        store: DownloadStore
    ) async -> DownloadJob? {
        guard let ytdlpPath, let ffmpegPath else { return nil }
        switch DownloadEngineRouter.selectEngine(for: record) {
        case .ytdlp:
            let extraArgs = YtDlpArgumentBuilder.build(
                record: record,
                cookies: bulkConfig.cookieArgsList,
                formatArgs: formatArgs,
                batchArgs: DownloadBatchRateLimiter.gentleSleepRequestsArgs(
                    kind: record.collectionKind ?? .multiURL,
                    batchCount: totalBulkCount
                ),
                options: bulkConfig.ytdlpOptions
            )
            return DownloadJob(
                recordID: record.id,
                url: record.url,
                destination: URL(fileURLWithPath: record.destinationPath),
                ytdlp: ytdlpPath,
                ffmpeg: ffmpegPath,
                extraArgs: extraArgs,
                collectionID: record.collectionID,
                collectionIndex: record.collectionIndex,
                enqueuedAt: record.created
            )
        case .douyinDirect:
            let resolved = try? await DouyinVideoClient.resolve(
                url: record.url,
                cookieFile: bulkConfig.cookieFileURL
            )
            var updated = record
            if let resolved {
                updated.douyinAwemeID = resolved.awemeId
                updated.videoTitle = resolved.title
                if updated.channelName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true,
                   !resolved.author.isEmpty
                {
                    updated.channelName = resolved.author
                }
                if updated.thumbnailURL?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true,
                   let thumbnail = resolved.thumbnailURL
                {
                    updated.thumbnailURL = thumbnail
                }
                updated.referer = DouyinAPISupport.origin
                updated.destinationPath = Self.backgroundConcreteDestination(
                    from: bulkConfig.dest,
                    title: updated.videoTitle,
                    author: updated.channelName,
                    fallbackID: resolved.awemeId,
                    ext: "mp4"
                ).path
                try? store.update(updated)
            }
            let target = URL(fileURLWithPath: updated.destinationPath)
            return DownloadJob(
                recordID: updated.id,
                url: resolved?.directURL ?? updated.url,
                destination: target,
                executable: ffmpegPath,
                arguments: {
                    var args = ["-y"]
                    if let referer = updated.referer?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                        ?? (resolved != nil ? DouyinAPISupport.origin : nil)
                    {
                        args += ["-referer", referer]
                    }
                    var headers = updated.customHeaders ?? [:]
                    if let extraHeaders = resolved?.downloadHeaders {
                        for (key, value) in extraHeaders {
                            headers[key] = value
                        }
                    }
                    if !headers.isEmpty {
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
                    args += ["-i", resolved?.directURL ?? updated.url, "-c", "copy", "-movflags", "+faststart", target.path]
                    return args
                }(),
                collectionID: updated.collectionID,
                collectionIndex: updated.collectionIndex,
                enqueuedAt: updated.created
            )
        case .ffmpegDirect:
            return DownloadJob(
                recordID: record.id,
                url: record.url,
                destination: URL(fileURLWithPath: record.destinationPath),
                executable: ffmpegPath,
                arguments: ["-y", "-i", record.url, "-c", "copy", "-movflags", "+faststart", record.destinationPath],
                collectionID: record.collectionID,
                collectionIndex: record.collectionIndex,
                enqueuedAt: record.created
            )
        }
    }

    nonisolated private static func resolveBulkDouyinRecords(
        _ records: [DownloadRecord],
        cookieFile: URL?
    ) async -> [Int: DouyinResolvedVideo] {
        let douyinEntries: [(Int, DownloadRecord)] = records.enumerated().compactMap { index, record in
            guard DownloadEngineRouter.selectEngine(for: record) == .douyinDirect else { return nil }
            return (index, record)
        }
        guard !douyinEntries.isEmpty else { return [:] }

        let maxConcurrent = min(4, douyinEntries.count)
        return await withTaskGroup(
            of: (Int, DouyinResolvedVideo?).self,
            returning: [Int: DouyinResolvedVideo].self
        ) { group in
            var nextIndex = 0

            func enqueueNext() {
                guard nextIndex < douyinEntries.count else { return }
                let (index, record) = douyinEntries[nextIndex]
                nextIndex += 1
                group.addTask {
                    let resolved = try? await DouyinVideoClient.resolve(
                        url: record.url,
                        cookieFile: cookieFile
                    )
                    return (index, resolved)
                }
            }

            for _ in 0..<maxConcurrent {
                enqueueNext()
            }

            var results: [Int: DouyinResolvedVideo] = [:]
            for await (index, resolved) in group {
                if let resolved {
                    results[index] = resolved
                }
                enqueueNext()
            }
            return results
        }
    }

    private struct BulkPreparation: Sendable {
        let dest: URL
        let cookieArgsList: [String]
        let cookieFileURL: URL?
        let ytdlpOptions: YtDlpArgumentOptions
    }

    nonisolated private static func prepareBulkConfiguration(collectionTitle: String) -> BulkPreparation {
        let useSubfolder = AppGroupSettings.defaults.object(forKey: "downloadCollectionSubfolder") as? Bool ?? true
        let dest = try? DownloadDestinationBuilder.destinationURL(
            collectionTitle: collectionTitle,
            useCollectionSubfolder: useSubfolder
        )
        let cookieArgsList = DownloadCookieConfiguration.bulkCookieArgs()
        let rawSpeedMode = AppGroupSettings.defaults.string(forKey: "downloadSpeedMode") ?? DownloadSpeedMode.balanced.rawValue
        let speedMode = DownloadSpeedMode(rawValue: rawSpeedMode) ?? .balanced
        let configuredFragments = AppGroupSettings.defaults.integer(forKey: "downloadConcurrentFragments")
        let concurrentFragments = configuredFragments > 0 ? configuredFragments : 4
        let sleepInterval = max(0, AppGroupSettings.defaults.double(forKey: "downloadSleepInterval"))
        let options = YtDlpArgumentOptions(
            concurrentFragments: concurrentFragments,
            sleepInterval: sleepInterval,
            speedMode: speedMode
        )
        let cookieFileURL = cookieArgsList.firstIndex(of: "--cookies").flatMap { idx -> URL? in
            guard cookieArgsList.indices.contains(idx + 1) else { return nil }
            return URL(fileURLWithPath: cookieArgsList[idx + 1])
        }
        return BulkPreparation(
            dest: dest ?? URL(fileURLWithPath: "/tmp"),
            cookieArgsList: cookieArgsList,
            cookieFileURL: cookieFileURL,
            ytdlpOptions: options
        )
    }

    func enqueue(
        url: String,
        title: String?,
        formatArgs: [String] = [],
        mediaType: String? = nil,
        referer: String? = nil,
        customHeaders: [String: String]? = nil,
        pageURL: String? = nil,
        douyinAwemeID: String? = nil,
        videoTitle: String? = nil,
        channelName: String? = nil,
        thumbnailURL: String? = nil
        ) async {
        let normalized = Self.normalizeDouyinExtensionDispatch(
            url: url,
            title: title,
            mediaType: mediaType,
            pageURL: pageURL,
            douyinAwemeID: douyinAwemeID
        )
        if helperBaseURL != nil {
            let forwarded = await sendSingleToHelper(
                url: normalized.url,
                title: title ?? normalized.url,
                mediaType: normalized.mediaType,
                referer: referer,
                customHeaders: customHeaders,
                pageURL: normalized.pageURL ?? normalized.url,
                douyinAwemeID: normalized.awemeID,
                formatArgs: formatArgs
            )
                if forwarded { return }
            }
        let initialState = initialEnqueueState()
        let payload = await Task.detached(priority: .userInitiated) { [normalized, title, referer, customHeaders, formatArgs, initialState, videoTitle, channelName, thumbnailURL] () -> (DownloadRecord, URL)? in
            do {
                let dest = try DownloadDestinationBuilder.destinationURL(
                    collectionTitle: nil,
                    useCollectionSubfolder: true
                )
                var record = DownloadRecord(
                    url: normalized.url,
                    title: title ?? normalized.url,
                    destinationPath: dest.path,
                    state: initialState
                )
                record.pageURL = normalized.pageURL ?? normalized.url
                record.mediaType = normalized.mediaType?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                record.douyinAwemeID = normalized.awemeID
                record.referer = referer?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                record.customHeaders = (customHeaders?.isEmpty == false) ? customHeaders : nil
                if let videoTitle = videoTitle?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty {
                    record.videoTitle = videoTitle
                }
                if let channelName = channelName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty {
                    record.channelName = channelName
                }
                if let thumbnailURL = thumbnailURL?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty {
                    record.thumbnailURL = thumbnailURL
                }
                record = DownloadMetadataFallback.applyingFallbacks(to: record, destinationPath: nil)
                return (record, dest)
            } catch {
                return nil
            }
        }.value
        guard let payload else {
            log.error("enqueue failed: unable to prepare destination")
            return
        }
        let insertedID = await Task.detached(priority: .userInitiated) { [store, record = payload.0] () -> RecordID? in
            do {
                try store.insert(record)
                return record.id
            } catch {
                return nil
            }
        }.value
        guard let insertedID else {
            log.error("enqueue failed: unable to persist record")
            return
        }
        if payload.0.state == .paused {
            Self.postStateChanged(id: insertedID, state: .paused)
        }
        let task = Task { [weak self] in
            guard let self else { return }
            await self.fetchMetadataThenStart(record: payload.0, url: normalized.url, dest: payload.1, formatArgs: formatArgs)
        }
        metadataFetchTasks[insertedID] = task
    }

    func pauseCollection(id: String) async {
        if helperBaseURL != nil {
            await sendAction(.pauseCollection, collectionID: id)
            return
        }
        guard let records = try? store.records(inCollection: id) else { return }
        await pauseDownloads(ids: records.filter { [.running, .queued].contains($0.state) }.map(\.id))
    }

    func resumeCollection(id: String) async {
        if helperBaseURL != nil {
            await sendAction(.resumeCollection, collectionID: id)
            return
        }
        guard let records = try? store.records(inCollection: id) else { return }
        await resumeDownloads(records: records.filter { record in
            record.state == .paused || record.state == .failed
        })
    }

    func deleteCollection(id: String, deleteFiles: Bool) async {
        guard let records = try? store.records(inCollection: id), !records.isEmpty else { return }

        if deleteFiles {
            await Task.detached(priority: .userInitiated) {
                DownloadDiskCleanup.deleteFiles(for: records)
            }.value
        }

        // File deletion always runs in the main app (full disk access). The helper
        // only needs to clear queue state and DB rows.
        if helperBaseURL != nil,
           await sendAction(.deleteCollection, collectionID: id, deleteFiles: false)
        {
            return
        }

        let ids = records.map(\.id)
        await deleteDownloads(ids: ids)
    }

    func pauseDownloads(ids: [RecordID]) async {
        guard !ids.isEmpty else { return }
        for id in ids {
            await queue.pauseForResume(id)
            try? store.updateState(id: id, to: .paused)
            Self.postStateChanged(id: id, state: .paused)
        }
    }

    func resumeDownloads(records: [DownloadRecord]) async {
        guard !records.isEmpty else { return }
        for record in records {
            await reenqueue(record: record)
        }
    }

    func deleteDownloadsWithFiles(records: [DownloadRecord]) async {
        guard !records.isEmpty else { return }
        let snapshot = records
        let ids = snapshot.map(\.id)
        log.info("deleteDownloadsWithFiles ids=\(ids.count), collection=\(snapshot.first?.collectionTitle ?? "nil")")
        await deleteDownloads(ids: ids)
        await Task.detached(priority: .userInitiated) {
            DownloadDiskCleanup.deleteFiles(for: snapshot)
        }.value
    }

    func cancelMetadataFetches(for ids: [RecordID]) {
        guard !ids.isEmpty else { return }
        for id in ids {
            cancelMetadataFetch(for: id)
        }
    }

    func postDeletedStateChanges(_ ids: [RecordID]) {
        guard !ids.isEmpty else { return }
        for id in ids {
            NotificationCenter.default.post(
                name: .downloadStateChanged,
                object: nil,
                userInfo: ["id": id.rawValue]
            )
        }
    }

    private func deleteDownloadWithFiles(record: DownloadRecord) async {
        await deleteDownload(id: record.id)
        await Task.detached(priority: .userInitiated) {
            DownloadDiskCleanup.deleteFiles(for: [record])
        }.value
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

    private func initialEnqueueState() -> DownloadState {
        guard let paused = try? store.list(state: .paused), !paused.isEmpty else {
            return .queued
        }
        let running = (try? store.list(state: .running)) ?? []
        let queued = (try? store.list(state: .queued)) ?? []
        if running.isEmpty && queued.isEmpty {
            return .paused
        }
        return .queued
    }

    private func fetchMetadataThenStart(
        record: DownloadRecord,
        url: String,
        dest: URL,
        formatArgs: [String] = [],
        requestCookieSync: Bool = true
    ) async {
        defer { metadataFetchTasks.removeValue(forKey: record.id) }
        guard !Task.isCancelled else { return }

        Self.postCrossProcessNotification(
            name: .downloadPhase,
            userInfo: ["id": record.id.rawValue, "phase": "Fetching info…"]
        )

        let (cookieArgsList, cookieHadErrors) = await Task.detached(priority: .utility) {
            Self.makeCookieArgs()
        }.value
        postCookieWarningIfNeeded(hadErrors: cookieHadErrors)
        let cookieFileURL = cookieFileURL(from: cookieArgsList)
        let selectedEngine = DownloadEngineRouter.selectEngine(for: record)
        let shouldFetchMetadata = selectedEngine != .ffmpegDirect && selectedEngine != .douyinDirect

        if shouldFetchMetadata {
            let needsTitle = record.videoTitle?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
            let needsThumbnail = record.thumbnailURL?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
            if needsTitle || needsThumbnail {
                guard let ytdlpPath = try? binaries.ytdlpPath() else { return }
                let metadata = await MetadataFetcher.fetch(url: url, ytdlp: ytdlpPath, cookieFile: cookieFileURL)
                if let meta = metadata {
                    var updated = record
                    if needsTitle, !meta.title.isEmpty {
                        updated.videoTitle = meta.title
                    }
                    if needsThumbnail, !meta.thumbnailURL.isEmpty {
                        updated.thumbnailURL = meta.thumbnailURL
                    }
                    if needsTitle, !meta.channelName.isEmpty {
                        updated.channelName = meta.channelName
                    }
                    if meta.durationSeconds > 0 {
                        updated.durationSeconds = meta.durationSeconds
                    }
                    updated.modified = Date()
                    try? store.update(updated)
                    Self.postStateChanged(id: record.id, state: updated.state)
                }
            }
        }

        guard !Task.isCancelled, shouldStillEnqueue(recordID: record.id) else { return }

        do {
            let latest = try store.fetch(id: record.id)
            try await startJob(
                for: latest,
                formatArgs: formatArgs,
                requestCookieSync: requestCookieSync
            )
        } catch {
            log.error("enqueue start failed: \(error.localizedDescription)")
            if var failed = try? store.fetch(id: record.id) {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                if !message.isEmpty {
                    failed.lastError = message
                }
                failed.state = .failed
                failed.modified = Date()
                try? store.update(failed)
            } else {
                try? store.updateState(id: record.id, to: .failed)
            }
            Self.postStateChanged(id: record.id, state: .failed)
        }
    }

    private func startJob(
        for record: DownloadRecord,
        formatArgs: [String] = [],
        requestCookieSync: Bool = true
    ) async throws {
        let record = try await persistNormalizedDouyinRecordIfNeeded(record)
        let dest = URL(fileURLWithPath: record.destinationPath)
        let (cookies, cookieHadErrors) = await Task.detached(priority: .utility) {
            Self.makeCookieArgs()
        }.value
        postCookieWarningIfNeeded(hadErrors: cookieHadErrors)
        let selectedEngine = DownloadEngineRouter.selectEngine(for: record)
        Self.postCrossProcessNotification(
            name: .downloadPhase,
            userInfo: ["id": record.id.rawValue, "phase": "\(selectedEngine.rawValue)…"]
        )
        var batchArgs: [String] = []
        if let kind = record.collectionKind, let collectionID = record.collectionID, !collectionID.isEmpty {
            let batchCount = (try? store.count(inCollection: collectionID)) ?? 1
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
            job = try await makeDouyinJob(
                record: record,
                destination: dest,
                cookies: cookies,
                formatArgs: formatArgs,
                batchArgs: batchArgs,
                requestCookieSync: requestCookieSync
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

    private func makeDouyinJob(
        record: DownloadRecord,
        destination: URL,
        cookies: [String],
        formatArgs: [String],
        batchArgs: [String],
        requestCookieSync: Bool
    ) async throws -> DownloadJob {
        guard record.url.localizedCaseInsensitiveContains("douyin.com") else {
            return try makeYtDlpJob(
                record: record,
                destination: destination,
                cookies: cookies,
                formatArgs: formatArgs,
                batchArgs: batchArgs + ["--no-playlist"]
            )
        }

        if requestCookieSync {
            await Self.requestDouyinCookieSyncIfPossible(dispatch: dispatch)
        }
        let (refreshedCookies, _) = Self.makeCookieArgs()
        let cookieFile = cookieFileURL(from: refreshedCookies) ?? cookieFileURL(from: cookies)

        let resolved = try await DouyinVideoClient.resolve(url: record.url, cookieFile: cookieFile)
        var updated = record
        updated.douyinAwemeID = resolved.awemeId
        updated.videoTitle = resolved.title
        if updated.channelName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true,
           !resolved.author.isEmpty
        {
            updated.channelName = resolved.author
        }
        if updated.thumbnailURL?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true,
           let thumbnail = resolved.thumbnailURL
        {
            updated.thumbnailURL = thumbnail
        }
        updated.referer = DouyinAPISupport.origin
        // ffmpeg cannot expand yt-dlp output templates (e.g. "%(title)s.%(ext)s");
        // resolve a concrete .mp4 path so it can open the output file.
        let concreteDestination = Self.concreteDestination(
            from: destination,
            title: updated.videoTitle,
            author: updated.channelName,
            fallbackID: resolved.awemeId,
            ext: "mp4"
        )
        updated.destinationPath = concreteDestination.path
        updated.modified = Date()
        try? store.update(updated)
        NotificationCenter.default.post(
            name: .downloadPhase,
            object: nil,
            userInfo: ["id": record.id.rawValue, "phase": "Downloading…"]
        )
        return try makeFfmpegDirectJob(
            record: updated,
            destination: concreteDestination,
            mediaURL: resolved.directURL,
            extraHeaders: resolved.downloadHeaders
        )
    }

    struct DouyinExtensionDispatchNormalization: Equatable {
        let url: String
        let pageURL: String?
        let awemeID: String?
        let mediaType: String?
    }

    nonisolated static func normalizeDouyinExtensionDispatch(
        url: String,
        title: String?,
        mediaType: String?,
        pageURL: String? = nil,
        douyinAwemeID: String? = nil
    ) -> DouyinExtensionDispatchNormalization {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard DouyinDownloadURLPatterns.prefersNativeResolve(url: trimmed) else {
            return DouyinExtensionDispatchNormalization(
                url: trimmed,
                pageURL: pageURL?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                awemeID: douyinAwemeID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                mediaType: mediaType?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            )
        }

        let awemeFromURL = DouyinVideoClient.extractAwemeID(from: trimmed)
        let awemeFromPage = pageURL.flatMap { DouyinVideoClient.extractAwemeID(from: $0) }
        let awemeFromTitle = DouyinDownloadURLPatterns.extractAwemeIDFromTitle(title)
        let awemeID = douyinAwemeID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? awemeFromURL
            ?? awemeFromPage
            ?? awemeFromTitle

        if let awemeID {
            let page = "https://www.douyin.com/video/\(awemeID)"
            return DouyinExtensionDispatchNormalization(url: page, pageURL: page, awemeID: awemeID, mediaType: nil)
        }

        return DouyinExtensionDispatchNormalization(
            url: trimmed,
            pageURL: pageURL?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            awemeID: nil,
            mediaType: mediaType?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        )
    }

    private func persistNormalizedDouyinRecordIfNeeded(_ record: DownloadRecord) async throws -> DownloadRecord {
        let normalized = Self.normalizeDouyinExtensionDispatch(
            url: record.url,
            title: record.title,
            mediaType: record.mediaType,
            pageURL: record.pageURL,
            douyinAwemeID: record.douyinAwemeID
        )
        guard normalized.url != record.url
            || normalized.pageURL != record.pageURL
            || normalized.awemeID != record.douyinAwemeID
            || normalized.mediaType != record.mediaType
        else {
            return record
        }
        var updated = record
        updated.url = normalized.url
        updated.pageURL = normalized.pageURL ?? normalized.url
        updated.douyinAwemeID = normalized.awemeID
        updated.mediaType = normalized.mediaType
        updated.modified = Date()
        try store.update(updated)
        return updated
    }

    private func ffmpegOutputExtension(record: DownloadRecord, destination: URL) -> String {
        if let mediaType = record.mediaType?.lowercased(), !mediaType.isEmpty {
            switch mediaType {
            case "jpeg", "jpg":
                return "jpg"
            case "mp3", "audio":
                return "mp3"
            default:
                return mediaType
            }
        }
        let ext = destination.pathExtension.lowercased()
        if !ext.isEmpty, !ext.contains("%") {
            return ext
        }
        return "mp4"
    }

    /// Resolves a literal output path, expanding any yt-dlp template placeholders
    /// (`%(...)s`) into a sanitized `<title> - <author>.<ext>` filename. ffmpeg
    /// cannot expand templates, so the native Douyin path needs a concrete file.
    nonisolated static func concreteDestination(
        from destination: URL,
        title: String?,
        author: String?,
        fallbackID: String,
        ext: String
    ) -> URL {
        let directory = destination.deletingLastPathComponent()
        let existingName = destination.lastPathComponent
        guard existingName.contains("%(") || destination.pathExtension.isEmpty else {
            return destination
        }
        func sanitize(_ value: String?) -> String {
            (value ?? "")
                .components(separatedBy: CharacterSet(charactersIn: "/\\:*?\"<>|\n\r\t"))
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let cleanTitle = sanitize(title)
        let cleanAuthor = sanitize(author)
        var base: String
        if !cleanTitle.isEmpty, !cleanAuthor.isEmpty {
            base = "\(cleanTitle) - \(cleanAuthor)"
        } else if !cleanTitle.isEmpty {
            base = cleanTitle
        } else {
            base = "douyin-\(fallbackID.isEmpty ? UUID().uuidString : fallbackID)"
        }
        if base.count > 180 { base = String(base.prefix(180)) }
        return directory.appendingPathComponent("\(base).\(ext)")
    }

    nonisolated private static func backgroundConcreteDestination(
        from destination: URL,
        title: String?,
        author: String?,
        fallbackID: String,
        ext: String
    ) -> URL {
        let directory = destination.deletingLastPathComponent()
        let existingName = destination.lastPathComponent
        guard existingName.contains("%(") || destination.pathExtension.isEmpty else {
            return destination
        }
        func sanitize(_ value: String?) -> String {
            (value ?? "")
                .components(separatedBy: CharacterSet(charactersIn: "/\\:*?\"<>|\n\r\t"))
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let cleanTitle = sanitize(title)
        let cleanAuthor = sanitize(author)
        var base: String
        if !cleanTitle.isEmpty, !cleanAuthor.isEmpty {
            base = "\(cleanTitle) - \(cleanAuthor)"
        } else if !cleanTitle.isEmpty {
            base = cleanTitle
        } else {
            base = "douyin-\(fallbackID.isEmpty ? UUID().uuidString : fallbackID)"
        }
        if base.count > 180 { base = String(base.prefix(180)) }
        return directory.appendingPathComponent("\(base).\(ext)")
    }

    nonisolated private static func requestDouyinCookieSyncIfPossible(dispatch: DispatchServer?) async {
        let mode = AppGroupSettings.defaults.string(forKey: "downloadCookieMode") ?? "browser_auto"
        guard mode == "extension_only" else { return }
        await dispatch?.requestCookieSync()
        for _ in 0 ..< 4 {
            try? await Task.sleep(nanoseconds: 500_000_000)
            let extFile = AppGroup.containerURL()
                .appendingPathComponent("cookies", isDirectory: true)
                .appendingPathComponent("downloader-extension-cookies.txt")
            if FileManager.default.fileExists(atPath: extFile.path) { return }
        }
    }

    private func makeFfmpegDirectJob(
        record: DownloadRecord,
        destination: URL,
        mediaURL: String? = nil,
        extraHeaders: [String: String]? = nil
    ) throws -> DownloadJob {
        let inputURL = mediaURL ?? record.url
        let outputExt = ffmpegOutputExtension(record: record, destination: destination)
        let outputDest = Self.concreteDestination(
            from: destination,
            title: record.videoTitle ?? record.title,
            author: record.channelName,
            fallbackID: record.douyinAwemeID ?? record.id.rawValue,
            ext: outputExt
        )
        var args = ["-y"]
        if let referer = record.referer?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? (mediaURL != nil ? DouyinAPISupport.origin : nil)
        {
            args += ["-referer", referer]
        }
        var headers = record.customHeaders ?? [:]
        if let extraHeaders {
            for (key, value) in extraHeaders {
                headers[key] = value
            }
        }
        if !headers.isEmpty {
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
        args += ["-i", inputURL, "-c", "copy", "-movflags", "+faststart", outputDest.path]
        return DownloadJob(
            recordID: record.id,
            url: inputURL,
            destination: outputDest,
            executable: try binaries.ffmpegPath(),
            arguments: args,
            collectionID: record.collectionID,
            collectionIndex: record.collectionIndex,
            enqueuedAt: record.created
        )
    }

    private func helperURL(_ path: String) -> URL? {
        helperBaseURL?.appendingPathComponent(path)
    }

    nonisolated private static func dispatchAuthorizationHeader() -> String? {
        let tokenURL = AppGroup.containerURL().appendingPathComponent("dispatch.token")
        guard let token = try? DispatchToken.read(at: tokenURL).trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty else { return nil }
        return "Bearer \(token)"
    }

    @discardableResult
    private func sendAction(
        _ action: DispatchServer.Action,
        recordID: String? = nil,
        collectionID: String? = nil,
        deleteFiles: Bool = false
    ) async -> Bool {
        guard let helperURL = helperURL("dispatch") else { return false }
        let body = DownloadBridgeRequest(
            action: action,
            url: nil,
            title: nil,
            urls: nil,
            entries: nil,
            type: nil,
            referer: nil,
            headers: nil,
            awemeId: nil,
            pageURL: nil,
            recordID: recordID,
            collectionID: collectionID,
            deleteFiles: deleteFiles
        )
        var request = URLRequest(url: helperURL)
        request.httpMethod = "POST"
        request.timeoutInterval = Self.helperRequestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let auth = Self.dispatchAuthorizationHeader() {
            request.setValue(auth, forHTTPHeaderField: "Authorization")
        }
        if let data = try? JSONEncoder().encode(body) {
            request.httpBody = data
            guard let (_, response) = try? await URLSession.shared.data(for: request),
                  let http = response as? HTTPURLResponse else { return false }
            return (200..<300).contains(http.statusCode)
        }
        return false
    }

    private func sendSingleToHelper(
        url: String,
        title: String?,
        mediaType: String?,
        referer: String?,
        customHeaders: [String: String]?,
        pageURL: String?,
        douyinAwemeID: String?,
        formatArgs: [String]
    ) async -> Bool {
        guard let helperURL = helperURL("dispatch") else { return false }
        let body = DownloadBridgeRequest(
            action: .enqueue,
            url: url,
            title: title,
            urls: nil,
            entries: nil,
            type: mediaType,
            referer: referer,
            headers: customHeaders,
            awemeId: douyinAwemeID,
            pageURL: pageURL,
            recordID: nil,
            collectionID: nil,
            deleteFiles: nil
        )
        var request = URLRequest(url: helperURL)
        request.httpMethod = "POST"
        request.timeoutInterval = Self.helperRequestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let auth = Self.dispatchAuthorizationHeader() {
            request.setValue(auth, forHTTPHeaderField: "Authorization")
        }
        if let data = try? JSONEncoder().encode(body) {
            request.httpBody = data
            guard let (_, response) = try? await URLSession.shared.data(for: request),
                  let http = response as? HTTPURLResponse else { return false }
            return (200..<300).contains(http.statusCode)
        }
        return false
    }

    nonisolated private static func sendBulkToHelper(
        helperBaseURL: URL,
        entries: [BulkEnqueueEntry],
        collectionTitle: String
    ) async -> Bool {
        let helperURL = helperBaseURL.appendingPathComponent("dispatch")
        let body = DownloadBridgeRequest(
            action: .bulkEnqueue,
            url: nil,
            title: collectionTitle,
            urls: entries.map(\.pageURL),
            entries: entries,
            type: nil,
            referer: nil,
            headers: nil,
            awemeId: nil,
            pageURL: nil,
            recordID: nil,
            collectionID: nil,
            deleteFiles: nil
        )
        var request = URLRequest(url: helperURL)
        request.httpMethod = "POST"
        request.timeoutInterval = Self.helperRequestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let auth = Self.dispatchAuthorizationHeader() {
            request.setValue(auth, forHTTPHeaderField: "Authorization")
        }
        if let data = try? JSONEncoder().encode(body) {
            request.httpBody = data
            guard let (_, response) = try? await URLSession.shared.data(for: request),
                  let http = response as? HTTPURLResponse else { return false }
            return (200..<300).contains(http.statusCode)
        }
        return false
    }

    private struct DownloadBridgeRequest: Codable {
        let action: DispatchServer.Action?
        let url: String?
        let title: String?
        let urls: [String]?
        let entries: [BulkEnqueueEntry]?
        let type: String?
        let referer: String?
        let headers: [String: String]?
        let awemeId: String?
        let pageURL: String?
        let recordID: String?
        let collectionID: String?
        let deleteFiles: Bool?
    }

    private func ytdlpArgumentOptions() -> YtDlpArgumentOptions {
        let defaults = AppGroupSettings.defaults
        let configuredFragments = defaults.integer(forKey: "downloadConcurrentFragments")
        let concurrentFragments = configuredFragments > 0 ? configuredFragments : 4
        let sleepInterval = max(0, defaults.double(forKey: "downloadSleepInterval"))
        let rawSpeedMode = defaults.string(forKey: "downloadSpeedMode") ?? DownloadSpeedMode.balanced.rawValue
        let speedMode = DownloadSpeedMode(rawValue: rawSpeedMode) ?? .balanced
        return YtDlpArgumentOptions(
            concurrentFragments: concurrentFragments,
            sleepInterval: sleepInterval,
            speedMode: speedMode
        )
    }

    private func cookieFileURL(from cookieArgsList: [String]) -> URL? {
        guard let idx = cookieArgsList.firstIndex(of: "--cookies"),
              cookieArgsList.indices.contains(idx + 1) else { return nil }
        return URL(fileURLWithPath: cookieArgsList[idx + 1])
    }

    nonisolated private static func postBulkStateChanged(count: Int) {
        postCrossProcessNotification(
            name: .downloadBulkChanged,
            userInfo: ["count": count]
        )
    }

    nonisolated private static func postCrossProcessNotification(
        name: Notification.Name,
        userInfo: [AnyHashable: Any]
    ) {
        let notification = Notification(name: name, object: nil, userInfo: userInfo)
        DistributedNotificationCenter.default().postNotificationName(
            notification.name,
            object: nil,
            userInfo: notification.userInfo
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
        Self.postCrossProcessNotification(
            name: .downloadInterruptedRecovery,
            userInfo: ["count": ids.count]
        )
        Self.postCrossProcessNotification(
            name: .downloadStateChanged,
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
    static let downloadBulkChanged = Notification.Name("downloadBulkChanged")
}

/// Mark the record as failed, persisting the yt-dlp error message when one is
/// attached. User-initiated cancellations get the bare state update so we don't
/// surface a misleading `Cocoa error 3072` string in the UI.
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
        if let path = destinationPath?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
           !path.contains("%(")
        {
            updated.destinationPath = path
        }
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

    static func resolvedThumbnailURL(for record: DownloadRecord) -> URL? {
        if let remote = remoteThumbnailURL(from: record.thumbnailURL) {
            return remote
        }
        let source = record.pageURL?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? record.url
        if let remote = remoteThumbnailURL(from: thumbnailURL(for: source)) {
            return remote
        }
        return localThumbnailURL(for: record.destinationPath)
    }

    static func hydrate(_ record: DownloadRecord) -> DownloadRecord {
        applyingFallbacks(to: record, destinationPath: record.destinationPath)
    }

    private static func remoteThumbnailURL(from string: String?) -> URL? {
        guard let trimmed = string?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty else {
            return nil
        }
        return URL(string: trimmed)
    }

    private static func localThumbnailURL(for destinationPath: String) -> URL? {
        guard !destinationPath.contains("%(") else { return nil }
        let stem = URL(fileURLWithPath: destinationPath).deletingPathExtension()
        for ext in ["jpg", "webp", "png"] {
            let candidate = stem.appendingPathExtension(ext)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
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
