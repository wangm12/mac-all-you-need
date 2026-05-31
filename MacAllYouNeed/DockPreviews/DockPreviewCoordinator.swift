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
    private var currentAppName: String = ""
    private var currentAppIcon: NSImage?
    private var panelAnchor: NSPoint = .zero
    private var isRunning = false
    private var dismissTask: Task<Void, Never>?

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
        observer.onHoverBegan = { [weak self] pid, appName in
            Task { @MainActor [weak self] in
                await self?.showPreview(for: pid, appName: appName)
            }
        }
        observer.onHoverEnded = { [weak self] in
            self?.scheduleDismiss()
        }
        observer.start()
    }

    func stop() {
        isRunning = false
        observer.stop()
        panel.dismiss()
        cache.clearAll()
        currentPID = nil
        dismissTask?.cancel()
        dismissTask = nil
    }

    private func scheduleDismiss() {
        dismissTask?.cancel()
        dismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            self?.panel.dismiss()
            self?.currentPID = nil
        }
    }

    private func cancelDismiss() {
        dismissTask?.cancel()
        dismissTask = nil
    }

    private func showPreview(for pid: pid_t, appName: String) async {
        cancelDismiss()
        currentPID = pid
        currentAppName = appName

        // Resolve the app icon from running applications or workspace.
        currentAppIcon = NSWorkspace.shared.runningApplications
            .first { $0.processIdentifier == pid }?
            .icon

        let mode = DockPreviewPermissionGate.currentMode()

        var entries = await enumerator.windows(for: pid)
        entries = DockPreviewWindowFilter.filter(entries)

        // If the app is running but has no on-screen windows yet, show a placeholder.
        if entries.isEmpty && pid != 0 {
            // Show a minimal panel with just the app header and no windows.
        }
        guard !entries.isEmpty, currentPID == pid else { return }
        _ = cache.update(entries: entries, for: pid)

        panelAnchor = NSEvent.mouseLocation
        presentPanel(for: pid, mode: mode)

        guard mode == .fullPreview else { return }
        for entry in entries {
            if let cached = thumbnailCache.get(windowID: entry.id) {
                cache.setThumbnail(cached, windowID: entry.id, pid: pid)
                presentPanel(for: pid, mode: mode)
                continue
            }
            Task { @MainActor [weak self] in
                guard let self, self.currentPID == pid else { return }
                if let thumb = await self.thumbnailService.capture(windowID: entry.id, scale: 2.0) {
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
        panel.show(
            appIcon: currentAppIcon,
            appName: currentAppName,
            entries: entries,
            mode: mode,
            at: panelAnchor
        ) { [weak self] entry in
            self?.raiseService.raise(entry: entry)
            self?.panel.dismiss()
            self?.currentPID = nil
        }
    }
}
