import AppKit
import Foundation
import Platform

@MainActor
@Observable
final class DockPreviewCoordinator {
    private let observer: DockHoverObserver
    private let enumerator: any WindowEnumerating
    private let thumbnailService: any ThumbnailCapturing
    private let cache: DockPreviewWindowCache
    private let thumbnailCache: DockPreviewThumbnailCache
    private let raiseService: DockPreviewRaiseService
    private let panel: DockPreviewPanel
    private var currentPID: pid_t?
    private var panelOrigin: CGPoint = .zero
    private var isRunning = false

    init(coordinator axCoordinator: AXObserverCoordinator) {
        observer = DockHoverObserver(coordinator: axCoordinator)
        enumerator = SystemWindowEnumerator()
        thumbnailService = DockPreviewThumbnailService()
        cache = DockPreviewWindowCache()
        thumbnailCache = DockPreviewThumbnailCache()
        raiseService = DockPreviewRaiseService()
        panel = DockPreviewPanel()
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        observer.onHoverBegan = { [weak self] pid, _ in
            Task { @MainActor [weak self] in
                await self?.showPreview(for: pid)
            }
        }
        observer.onHoverEnded = { [weak self] in
            self?.panel.dismiss()
            self?.currentPID = nil
        }
        observer.start()
    }

    func stop() {
        isRunning = false
        observer.stop()
        panel.dismiss()
        cache.clearAll()
        currentPID = nil
    }

    private func showPreview(for pid: pid_t) async {
        currentPID = pid
        let mode = DockPreviewPermissionGate.currentMode()

        // Enumerate windows.
        var entries = await enumerator.windows(for: pid)
        entries = DockPreviewWindowFilter.filter(entries)
        guard !entries.isEmpty, currentPID == pid else { return }
        _ = cache.update(entries: entries, for: pid)

        // Anchor the panel near the cursor once, so it does not jump as
        // thumbnails stream in.
        let cursor = NSEvent.mouseLocation
        panelOrigin = CGPoint(x: cursor.x - 100, y: cursor.y + 10)
        presentPanel(for: pid, mode: mode)

        // Load thumbnails asynchronously when Screen Recording is available.
        guard mode == .fullPreview else { return }
        for entry in entries {
            if let cached = thumbnailCache.get(windowID: entry.id) {
                cache.setThumbnail(cached, windowID: entry.id, pid: pid)
                presentPanel(for: pid, mode: mode)
                continue
            }
            Task { @MainActor [weak self] in
                guard let self, self.currentPID == pid else { return }
                if let thumb = await self.thumbnailService.capture(windowID: entry.id, scale: 1.5) {
                    guard self.currentPID == pid else { return }
                    self.thumbnailCache.set(windowID: entry.id, image: thumb)
                    self.cache.setThumbnail(thumb, windowID: entry.id, pid: pid)
                    self.presentPanel(for: pid, mode: mode)
                }
            }
        }
    }

    private func presentPanel(for pid: pid_t, mode: DockPreviewPermissionGate.Mode) {
        guard currentPID == pid else { return }
        let entries = DockPreviewWindowFilter.filter(cache.entries(for: pid))
        guard !entries.isEmpty else { return }
        panel.show(entries: entries, mode: mode, at: panelOrigin) { [weak self] entry in
            self?.raiseService.raise(entry: entry)
            self?.panel.dismiss()
            self?.currentPID = nil
        }
    }
}
