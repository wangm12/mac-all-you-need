import AppKit
import Core
import FeatureCore
import Foundation
import os
import Platform

/// Background work for dock window previews: disk thumbnail loads and heavy enumeration.
actor DockPreviewWorker: FeatureWorker {
    private var isRunning = false

    func start() async {
        guard !isRunning else { return }
        isRunning = true
    }

    func stop() async {
        isRunning = false
    }

    func beginRefreshApp(pid: pid_t) -> OSSignpostID {
        PerformanceSignpost.DockCapture.beginRefreshApp(pid: pid)
    }

    func endRefreshApp(_ id: OSSignpostID) {
        PerformanceSignpost.DockCapture.endRefreshApp(id)
    }

    /// Loads JPEG thumbnails off the main thread for visible preview rows.
    func hydrateEntries(
        _ entries: [DockPreviewWindowEntry],
        diskStore: DockPreviewThumbnailDiskStore
    ) async -> [DockPreviewWindowEntry] {
        let signpost = PerformanceSignpost.DockCapture.beginDiskHydrate(count: entries.count)
        defer { PerformanceSignpost.DockCapture.endDiskHydrate(signpost) }

        return await withTaskGroup(of: (Int, NSImage?).self, returning: [DockPreviewWindowEntry].self) { group in
            for (index, entry) in entries.enumerated() {
                group.addTask {
                    let image = await diskStore.loadImageAsync(
                        pid: entry.pid,
                        windowID: entry.id,
                        title: entry.title
                    )
                    return (index, image)
                }
            }
            var images: [Int: NSImage] = [:]
            for await (index, image) in group {
                if let image { images[index] = image }
            }
            return entries.enumerated().map { index, entry in
                var copy = entry
                copy.thumbnail = images[index]
                return copy
            }
        }
    }

    /// Window enumeration + purify inputs run off the main actor; cache mutation stays on MainActor.
    func enumerateWindows(
        enumerator: any WindowEnumerating,
        pid: pid_t,
        settings: DockPreviewSettings,
        bundleIdentifier: String?,
        disableMinWindowSizeFilter: Bool
    ) async -> [DockPreviewWindowEntry] {
        await enumerator.windows(
            for: pid,
            settings: settings,
            bundleIdentifier: bundleIdentifier,
            disableMinWindowSizeFilter: disableMinWindowSizeFilter
        )
    }
}
