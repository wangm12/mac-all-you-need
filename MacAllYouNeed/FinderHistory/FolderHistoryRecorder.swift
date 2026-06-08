import AppKit
import ApplicationServices
import Core
import Foundation
import Platform

/// Records folder navigation in Finder via AX notifications (with workspace activation hooks).
@MainActor
final class FolderHistoryRecorder {
    private let store: FolderHistoryStore
    private let axReader: FolderHistoryAXReader
    private let coordinator: AXObserverCoordinator
    private let settings: () -> FolderHistorySettings
    private let historyWorker: FolderHistoryFeatureWorker?
    private let log = Logging.logger(for: "folder-history", category: "recorder")

    private var lastPath: String?
    private var lastDate: Date?
    private var isRunning = false
    private var workspaceObserver: NSObjectProtocol?
    private var finderPID: pid_t?
    private var finderPollTask: Task<Void, Never>?

    init(
        store: FolderHistoryStore,
        coordinator: AXObserverCoordinator,
        axReader: FolderHistoryAXReader = SystemFolderHistoryAXReader(),
        settings: @escaping () -> FolderHistorySettings = { FolderHistorySettingsStore.load() },
        historyWorker: FolderHistoryFeatureWorker? = nil
    ) {
        self.store = store
        self.coordinator = coordinator
        self.axReader = axReader
        self.settings = settings
        self.historyWorker = historyWorker
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        if !AXIsProcessTrusted() {
            log.warning("Accessibility not granted — Finder folder paths cannot be read.")
        }
        installWorkspaceObserver()
        attachFinderObserver()
        sampleFinderNow()
        startFinderPoll()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        stopFinderPoll()
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
            self.workspaceObserver = nil
        }
        coordinator.stop()
        finderPID = nil
    }

    func record(path: String, now: Date = Date()) {
        let cfg = settings()
        guard !cfg.isPaused else { return }
        guard !FolderHistorySkipRules.shouldSkip(path: path, exclusions: Set(cfg.excludedPaths)) else { return }
        guard FolderHistoryDedup.shouldRecord(
            newPath: path, lastPath: lastPath, lastDate: lastDate, now: now
        ) else { return }
        lastPath = path
        lastDate = now
        if let historyWorker {
            Task { @MainActor in
                do {
                    let persisted = try await historyWorker.persistVisit(
                        store: self.store,
                        path: path,
                        retentionMax: cfg.retentionMax,
                        now: now
                    )
                    if persisted { return }
                    _ = try self.store.upsert(path: path, now: now)
                    try self.store.evictStale(maxCount: cfg.retentionMax)
                } catch {
                    self.log.error(
                        "Failed to record folder visit at \(path, privacy: .public): \(error.localizedDescription, privacy: .public)"
                    )
                }
            }
            return
        }
        do {
            _ = try store.upsert(path: path, now: now)
            try store.evictStale(maxCount: cfg.retentionMax)
        } catch {
            log.error("Failed to record folder visit at \(path, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    func handleFinderEvent(pid: pid_t) {
        guard let path = FolderHistoryFinderPathResolver.resolve(pid: pid, axReader: axReader) else { return }
        record(path: path)
    }

    private func installWorkspaceObserver() {
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self, self.isRunning else { return }
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier == "com.apple.finder"
            else { return }
            self.attachFinderObserver(pid: app.processIdentifier)
            self.handleFinderEvent(pid: app.processIdentifier)
        }
    }

    private func attachFinderObserver(pid: pid_t? = nil) {
        guard let finderPID = pid ?? finderProcessIdentifier() else {
            coordinator.stop()
            self.finderPID = nil
            return
        }
        if self.finderPID == finderPID {
            handleFinderEvent(pid: finderPID)
            return
        }
        self.finderPID = finderPID
        coordinator.start(
            pid: finderPID,
            notifications: [
                kAXFocusedWindowChangedNotification as String,
                kAXTitleChangedNotification as String,
                kAXFocusedUIElementChangedNotification as String,
            ]
        ) { [weak self] _, eventPID in
            Task { @MainActor in
                self?.handleFinderEvent(pid: eventPID)
            }
        }
    }

    private func sampleFinderNow() {
        guard let pid = finderProcessIdentifier() else { return }
        let frontmostID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        guard frontmostID == "com.apple.finder" || frontmostID == Bundle.main.bundleIdentifier else { return }
        handleFinderEvent(pid: pid)
    }

    /// While Finder is frontmost, re-sample on the debounce interval. In-window navigation
    /// often updates the document path without a focused-window AX notification.
    private func startFinderPoll() {
        finderPollTask?.cancel()
        finderPollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self, self.isRunning else { return }
                guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder",
                      let pid = self.finderProcessIdentifier()
                else { continue }
                self.handleFinderEvent(pid: pid)
            }
        }
    }

    private func stopFinderPoll() {
        finderPollTask?.cancel()
        finderPollTask = nil
    }

    private func finderProcessIdentifier() -> pid_t? {
        NSWorkspace.shared.runningApplications
            .first { $0.bundleIdentifier == "com.apple.finder" }?
            .processIdentifier
    }

}
