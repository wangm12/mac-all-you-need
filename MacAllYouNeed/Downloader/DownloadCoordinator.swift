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
    let binaries: BinaryManager
    var dispatch: DispatchServer?
    private let log = Logging.logger(for: "downloader", category: "coordinator")

    init() throws {
        let key = try KeyManager(keychain: SystemKeychain()).deviceKey()
        let dbURL = AppGroup.containerURL().appendingPathComponent("databases/downloads.sqlite")
        let db = try Database(url: dbURL, migrations: DownloadStore.migrations)
        store = try DownloadStore(database: db, deviceKey: key)
        binaries = BinaryManager(bundleResources: Bundle.main.resourceURL!)
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
                    case .failure:
                        try? storeRef.updateState(id: id, to: .failed)
                        Self.postStateChanged(id: id, state: .failed)
                    }
                }
            }
        )
    }

    nonisolated static func cookieArguments(
        cookieFileURL: URL,
        prepare: (URL) throws -> Void
    ) -> [String] {
        do {
            try FileManager.default.createDirectory(
                at: cookieFileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try prepare(cookieFileURL)
            return ["--cookies", cookieFileURL.path]
        } catch {
            return []
        }
    }

    private static func postStateChanged(id: RecordID, state: DownloadState) {
        NotificationCenter.default.post(
            name: .downloadStateChanged, object: nil,
            userInfo: ["id": id.rawValue, "state": state.rawValue]
        )
    }

    private func cookieArgs() -> [String] {
        let cookieFile = AppGroup.containerURL()
            .appendingPathComponent("cookies", isDirectory: true)
            .appendingPathComponent("downloader-cookies.txt")
        let args = Self.cookieArguments(cookieFileURL: cookieFile) { url in
            try CookieImporter.combinedCookiesFile(at: url)
        }
        if args.isEmpty {
            NSLog("🍪 cookieArgs: EMPTY — cookie file generation failed, proceeding without cookies")
        } else {
            let lines = (try? String(contentsOfFile: args[1], encoding: .utf8))?.components(separatedBy: "\n").count ?? 0
            let firstLine = (try? String(contentsOfFile: args[1], encoding: .utf8))?.components(separatedBy: "\n").first ?? "?"
            NSLog("🍪 cookieArgs: \(args[1]) (\(lines) lines, first='\(firstLine)')")
        }
        return args
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
            let job = try DownloadJob(
                recordID: record.id, url: record.url, destination: dest,
                ytdlp: binaries.ytdlpPath(), ffmpeg: binaries.ffmpegPath(),
                extraArgs: cookieArgs()
            )
            await queue.enqueue(job)
        } catch {
            log.error("reenqueue failed: \(error.localizedDescription)")
        }
    }

    func cancelDownload(id: RecordID) async {
        await queue.cancel(id)
        try? store.updateState(id: id, to: .failed)
        Self.postStateChanged(id: id, state: .failed)
    }

    func deleteDownload(id: RecordID) async {
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
            let job = try DownloadJob(
                recordID: record.id, url: record.url, destination: dest,
                ytdlp: binaries.ytdlpPath(), ffmpeg: binaries.ffmpegPath(),
                extraArgs: ["--continue"] + cookieArgs()
            )
            await queue.enqueue(job)
            Self.postStateChanged(id: id, state: .running)
        } catch {
            log.error("resumeDownload failed: \(error.localizedDescription)")
        }
    }

    func enqueue(url: String, title: String?) async {
        do {
            let downloadsDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: "/tmp")
            let outputDir = downloadsDir.appendingPathComponent("MacAllYouNeed", isDirectory: true)
            try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
            // Use string concatenation — URL.appendingPathComponent percent-encodes % signs
            let destPath = outputDir.path + "/%(title)s - %(uploader)s.%(ext)s"
            let dest = URL(fileURLWithPath: destPath)
            let record = DownloadRecord(url: url, title: title ?? url, destinationPath: dest.path, state: .queued)
            try store.insert(record)
            let ytdlp = try binaries.ytdlpPath()
            let ffmpeg = try binaries.ffmpegPath()
            let cookies = cookieArgs()
            NSLog("▶️ enqueue: url=\(url)")
            NSLog("▶️ enqueue: ytdlp=\(ytdlp.path)")
            NSLog("▶️ enqueue: cookies=\(cookies), url=\(url)")
            let job = DownloadJob(
                recordID: record.id, url: url, destination: dest,
                ytdlp: ytdlp, ffmpeg: ffmpeg,
                extraArgs: cookies
            )
            await queue.enqueue(job)
            // Fetch metadata on MainActor-inherited Task (avoids Sendable capture issues with Task.detached)
            let recordID = record.id
            Task(priority: .background) { [weak self] in
                guard let self else { return }
                guard let ytdlpPath = try? self.binaries.ytdlpPath(),
                      let meta = await MetadataFetcher.fetch(url: url, ytdlp: ytdlpPath)
                else {
                    NSLog("🎬 MetadataFetcher: nil result for \(url)")
                    return
                }
                NSLog("🎬 MetadataFetcher: got title='\(meta.title)' channel='\(meta.channelName)'")
                guard var updated = try? self.store.fetch(id: recordID) else { return }
                updated.videoTitle = meta.title
                updated.channelName = meta.channelName
                updated.durationSeconds = meta.durationSeconds
                updated.thumbnailURL = meta.thumbnailURL
                updated.modified = Date()
                do {
                    try self.store.update(updated)
                    Self.postStateChanged(id: recordID, state: updated.state)
                    NSLog("🎬 MetadataFetcher: saved for id=\(recordID.rawValue.prefix(8))")
                } catch {
                    NSLog("🎬 MetadataFetcher: update failed: \(error)")
                }
            }
        } catch {
            NSLog("❌ enqueue FAILED: \(error)")
            log.error("enqueue failed: \(error.localizedDescription)")
        }
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
}
