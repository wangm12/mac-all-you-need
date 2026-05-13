import Core
import Foundation
import SwiftUI

@MainActor
@Observable
final class DownloaderViewModel {
    let coordinator: DownloadCoordinator
    var rows: [DownloadRecord] = []
    var liveProgress: [String: DownloadProgress] = [:]
    var liveStatus: [String: String] = [:]
    var cookieWarning: String?
    // Selection state — lives here so NSEvent monitors can capture `vm` (a reference type)
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

    init(coordinator: DownloadCoordinator) {
        self.coordinator = coordinator

        NotificationCenter.default.addObserver(
            forName: .downloadProgress, object: nil, queue: .main
        ) { [weak self] note in
            guard let self,
                  let id = note.userInfo?["id"] as? String,
                  let p = note.userInfo?["progress"] as? DownloadProgress else { return }
            self.handleProgress(id: id, p: p)
        }
        NotificationCenter.default.addObserver(
            forName: .downloadPhase, object: nil, queue: .main
        ) { [weak self] note in
            guard let id = note.userInfo?["id"] as? String,
                  let phase = note.userInfo?["phase"] as? String else { return }
            self?.liveStatus[id] = phase
        }
        NotificationCenter.default.addObserver(
            forName: .downloadStateChanged, object: nil, queue: .main
        ) { [weak self] note in
            guard let id = note.userInfo?["id"] as? String else { return }
            Task { @MainActor in
                await self?.refresh()
                if let state = note.userInfo?["state"] as? String,
                   ["completed", "failed", "paused"].contains(state)
                {
                    self?.liveProgress.removeValue(forKey: id)
                    self?.liveStatus.removeValue(forKey: id)
                    self?.speedSamples.removeValue(forKey: id)
                    self?.lastDisplayUpdate.removeValue(forKey: id)
                }
            }
        }
        NotificationCenter.default.addObserver(
            forName: .downloadDestinationPath, object: nil, queue: .main
        ) { [weak self] note in
            guard let id = note.userInfo?["id"] as? String,
                  let path = note.userInfo?["path"] as? String else { return }
            self?.liveDestination[id] = path
        }
        NotificationCenter.default.addObserver(
            forName: .cookieWarning, object: nil, queue: .main
        ) { [weak self] _ in
            self?.cookieWarning = "Some browser profiles could not be imported. Downloads requiring login may fail."
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

    func refresh() async {
        let ids = (try? coordinator.store.list()) ?? []
        rows = ids.compactMap { try? coordinator.store.fetch(id: $0) }
    }

    func add(url: String) async {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, URL(string: trimmed)?.scheme != nil else {
            CopyHUD.show("Invalid URL", symbol: "exclamationmark.triangle.fill")
            return
        }
        await coordinator.enqueue(url: trimmed, title: nil)
        await refresh()
        CopyHUD.show("Added to Downloads", symbol: "arrow.down.circle.fill")
    }

    func retry(record: DownloadRecord) async {
        await coordinator.reenqueue(record: record)
        await refresh()
        CopyHUD.show("Retrying", symbol: "arrow.clockwise.circle.fill")
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
