import AppKit
import ApplicationServices
import Core
import Foundation
import Platform

/// Records folder navigation events from Finder via AX observation.
///
/// Owned by AppController. Consumes the shared `AXObserverCoordinator` (S1):
/// subscribes to Finder's focused-window-changed notification, reads the
/// document path off the focused window, applies skip/dedup rules, and upserts
/// into the `FolderHistoryStore`. Finder can quit/relaunch, so a lightweight
/// poller re-subscribes when Finder's PID changes.
@MainActor
final class FolderHistoryRecorder {
    private let store: FolderHistoryStore
    private let coordinator: AXObserverCoordinator
    private let axReader: FolderHistoryAXReader
    private let exclusions: () -> Set<String>
    private let retentionMax: Int

    private var lastPath: String?
    private var lastDate: Date?
    private var isRunning = false
    private var finderPID: pid_t?
    private var finderPIDTask: Task<Void, Never>?

    init(
        store: FolderHistoryStore,
        coordinator: AXObserverCoordinator,
        axReader: FolderHistoryAXReader = SystemFolderHistoryAXReader(),
        exclusions: @escaping () -> Set<String> = { [] },
        retentionMax: Int = 500
    ) {
        self.store = store
        self.coordinator = coordinator
        self.axReader = axReader
        self.exclusions = exclusions
        self.retentionMax = retentionMax
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        observeFinder()
        startFinderPIDMonitor()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        coordinator.stop()
        finderPIDTask?.cancel()
        finderPIDTask = nil
        finderPID = nil
    }

    private func observeFinder() {
        guard let pid = findFinderPID() else { return }
        finderPID = pid
        coordinator.start(pid: pid, notifications: [kAXFocusedWindowChangedNotification as String]) { [weak self] _, pid in
            Task { @MainActor [weak self] in
                self?.handleFinderEvent(pid: pid)
            }
        }
        // Record the folder already focused at subscription time.
        handleFinderEvent(pid: pid)
    }

    /// Reads the focused Finder window's folder path and records it if it passes
    /// the skip and dedup rules. Internal so tests can drive it directly.
    func handleFinderEvent(pid: pid_t) {
        guard let path = focusedFolderPath(pid: pid) else { return }
        record(path: path)
    }

    /// Pure-ish recording step (no AX): applies skip + dedup, then upserts.
    /// Internal for unit testing without an accessibility connection.
    func record(path: String, now: Date = Date()) {
        guard !FolderHistorySkipRules.shouldSkip(path: path, exclusions: exclusions()) else { return }
        guard FolderHistoryDedup.shouldRecord(
            newPath: path, lastPath: lastPath, lastDate: lastDate, now: now
        ) else { return }
        lastPath = path
        lastDate = now
        do {
            _ = try store.upsert(path: path, now: now)
            try store.evictStale(maxCount: retentionMax)
        } catch {
            // Best-effort recording; a single failure should not crash dictation-like flows.
        }
    }

    private func focusedFolderPath(pid: pid_t) -> String? {
        let app = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let window = value
        else { return nil }
        // Force-cast is safe: AX focused-window attribute always returns an AXUIElement.
        // swiftlint:disable:next force_cast
        return axReader.documentPath(for: window as! AXUIElement)
    }

    private func findFinderPID() -> pid_t? {
        NSWorkspace.shared.runningApplications
            .first { $0.bundleIdentifier == "com.apple.finder" }?
            .processIdentifier
    }

    private func startFinderPIDMonitor() {
        finderPIDTask?.cancel()
        finderPIDTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard let self, self.isRunning, !Task.isCancelled else { return }
                if let newPID = self.findFinderPID(), newPID != self.finderPID {
                    self.coordinator.stop()
                    self.observeFinder()
                }
            }
        }
    }
}
