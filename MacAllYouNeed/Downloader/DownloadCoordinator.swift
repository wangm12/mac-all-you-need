import Core
import CryptoKit
import Foundation

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
            started: { id in Task { @MainActor in try? storeRef.updateState(id: id, to: .running) } },
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
                    case .success: try? storeRef.updateState(id: id, to: .completed)
                    case .failure: try? storeRef.updateState(id: id, to: .failed)
                    }
                }
            }
        )
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
                extraArgs: ["--continue"]
            )
            await queue.enqueue(job)
        } catch {
            log.error("reenqueue failed: \(error.localizedDescription)")
        }
    }

    func cancelDownload(id: RecordID) async {
        await queue.cancel(id)
        try? store.updateState(id: id, to: .failed)
    }

    func enqueue(url: String, title: String?) async {
        do {
            let dest = (FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: "/tmp"))
                .appendingPathComponent("%(title)s [%(id)s].%(ext)s")
            let record = DownloadRecord(url: url, title: title ?? url, destinationPath: dest.path, state: .queued)
            try store.insert(record)
            let ytdlp = try binaries.ytdlpPath()
            let ffmpeg = try binaries.ffmpegPath()
            NSLog("DownloadCoordinator: ytdlp=\(ytdlp.path) ffmpeg=\(ffmpeg.path)")
            let job = DownloadJob(
                recordID: record.id, url: url, destination: dest,
                ytdlp: ytdlp, ffmpeg: ffmpeg,
                extraArgs: []
            )
            NSLog("DownloadCoordinator: enqueuing job for \(url)")
            await queue.enqueue(job)
        } catch {
            NSLog("DownloadCoordinator: enqueue FAILED — \(error)")
            log.error("enqueue failed: \(error.localizedDescription)")
        }
    }

    func recoverInFlight() async {
        do {
            let ids = try store.list(state: .running)
            for id in ids {
                let r = try store.fetch(id: id)
                let dest = URL(fileURLWithPath: r.destinationPath)
                let job = try DownloadJob(
                    recordID: r.id, url: r.url, destination: dest,
                    ytdlp: binaries.ytdlpPath(), ffmpeg: binaries.ffmpegPath(),
                    extraArgs: ["--continue"]
                )
                await queue.enqueue(job)
            }
        } catch {
            log.error("recover failed: \(error.localizedDescription)")
        }
    }
}

public extension Notification.Name {
    static let downloadProgress = Notification.Name("downloadProgress")
}
