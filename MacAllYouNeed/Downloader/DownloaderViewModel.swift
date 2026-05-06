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
        try? coordinator.store.updateState(id: record.id, to: .queued)
        await coordinator.enqueue(url: record.url, title: record.title)
        await refresh()
    }

    func delete(ids: [RecordID]) async {
        for id in ids {
            await coordinator.queue.cancel(id)
            try? coordinator.store.updateState(id: id, to: .failed)
        }
        await refresh()
    }

    func clearStaleQueued() async {
        let stale = rows.filter { $0.state == .queued }
        for r in stale {
            try? coordinator.store.updateState(id: r.id, to: .failed)
        }
        await refresh()
    }
}
