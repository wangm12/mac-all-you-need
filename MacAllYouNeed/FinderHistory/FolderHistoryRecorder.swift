import AppKit
import ApplicationServices
import Core
import Foundation
import Platform

/// Records folder navigation events from Finder via polling.
///
/// Owned by AppController. Every 1.5s checks if Finder is frontmost, reads the
/// focused window's document path, and records if it changed. This avoids relying
/// on `kAXFocusedWindowChangedNotification` which does not fire during
/// within-window folder navigation.
@MainActor
final class FolderHistoryRecorder {
    private let store: FolderHistoryStore
    private let axReader: FolderHistoryAXReader
    private let exclusions: () -> Set<String>
    private let retentionMax: Int

    private var lastPath: String?
    private var lastDate: Date?
    private var isRunning = false
    private var pollTask: Task<Void, Never>?
    private var pollInterval: TimeInterval

    init(
        store: FolderHistoryStore,
        coordinator: AXObserverCoordinator? = nil, // kept for API compat, unused
        axReader: FolderHistoryAXReader = SystemFolderHistoryAXReader(),
        exclusions: @escaping () -> Set<String> = { [] },
        retentionMax: Int = 500,
        pollInterval: TimeInterval = 1.5
    ) {
        self.store = store
        self.axReader = axReader
        self.exclusions = exclusions
        self.retentionMax = retentionMax
        self.pollInterval = pollInterval
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        startPolling()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        pollTask?.cancel()
        pollTask = nil
    }

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
        } catch {}
    }

    // Internal for tests
    func handleFinderEvent(pid: pid_t) {
        guard let path = focusedFolderPath(pid: pid) else { return }
        record(path: path)
    }

    private func startPolling() {
        pollTask?.cancel()
        let interval = pollInterval
        pollTask = Task { @MainActor [weak self] in
            while let self, self.isRunning, !Task.isCancelled {
                self.pollFinder()
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    private func pollFinder() {
        guard let finderApp = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == "com.apple.finder"
        }) else { return }

        // Record when Finder is frontmost OR when MAYN is frontmost (user checking history)
        // but skip other unrelated foreground apps to avoid unnecessary AX reads.
        let frontmostID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        guard frontmostID == "com.apple.finder"
            || frontmostID == Bundle.main.bundleIdentifier
        else { return }

        let pid = finderApp.processIdentifier
        handleFinderEvent(pid: pid)
    }

    private func focusedFolderPath(pid: pid_t) -> String? {
        let app = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let window = value
        else { return nil }
        // swiftlint:disable:next force_cast
        return axReader.documentPath(for: window as! AXUIElement)
    }
}
