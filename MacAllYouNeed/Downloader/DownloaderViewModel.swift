import Core
import Foundation
import SwiftUI

@MainActor
@Observable
final class DownloaderViewModel {
    let coordinator: DownloadCoordinator
    var rows: [DownloadRecord] = []
    var liveProgress: [String: DownloadProgress] = [:]

    init(coordinator: DownloadCoordinator) {
        self.coordinator = coordinator
        NotificationCenter.default.addObserver(
            forName: .downloadProgress, object: nil, queue: .main
        ) { [weak self] note in
            guard let id = note.userInfo?["id"] as? String,
                  let p = note.userInfo?["progress"] as? DownloadProgress else { return }
            self?.liveProgress[id] = p
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
                }
            }
        }
        Task { await self.refresh() }
    }

    func refresh() async {
        let ids = (try? coordinator.store.list()) ?? []
        rows = ids.compactMap { try? coordinator.store.fetch(id: $0) }
    }

    func add(url: String) async {
        await coordinator.enqueue(url: url, title: nil)
        await refresh()
    }

    func retry(record: DownloadRecord) async {
        await coordinator.reenqueue(record: record)
        await refresh()
    }

    func cancel(id: RecordID) async {
        // Stop button — cancel and keep record as Failed so user can ↺ retry
        liveProgress.removeValue(forKey: id.rawValue)
        await coordinator.cancelDownload(id: id)
        await refresh()
    }

    func pause(id: RecordID) async {
        liveProgress.removeValue(forKey: id.rawValue)
        await coordinator.pauseDownload(id: id)
        await refresh()
    }

    func resume(id: RecordID) async {
        await coordinator.resumeDownload(id: id)
        await refresh()
    }

    func delete(ids: [RecordID]) async {
        for id in ids {
            liveProgress.removeValue(forKey: id.rawValue)
            await coordinator.deleteDownload(id: id)
        }
        await refresh()
    }
}
