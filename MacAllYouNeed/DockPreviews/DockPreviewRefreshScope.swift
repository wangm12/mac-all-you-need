import AppKit
import Foundation

/// Limits `refreshApp` and per-app AX window observers to dock-hover and switcher needs.
@MainActor
final class DockPreviewRefreshScope {
    static let recentHoverTTL: TimeInterval = 60
    static let idleDetachDelay: TimeInterval = 120

    private var recentHoveredAt: [pid_t: Date] = [:]
    private var currentHoveredPID: pid_t?
    private var switcherPIDs: Set<pid_t> = []
    private var panelVisible = false
    private var pendingShow = false
    private var lastDockActivity = Date.distantPast

    var isIdle: Bool {
        !panelVisible && !pendingShow
            && Date().timeIntervalSince(lastDockActivity) >= Self.idleDetachDelay
    }

    func noteDockProximity() {
        lastDockActivity = Date()
    }

    func noteHover(pid: pid_t) {
        lastDockActivity = Date()
        if pid != 0 {
            currentHoveredPID = pid
            recentHoveredAt[pid] = Date()
        }
    }

    func noteHoverEnded() {
        currentHoveredPID = nil
    }

    func setPanelVisible(_ visible: Bool) {
        panelVisible = visible
        if visible { lastDockActivity = Date() }
    }

    func setPendingShow(_ pending: Bool) {
        pendingShow = pending
        if pending { lastDockActivity = Date() }
    }

    func noteSwitcherSession(pids: [pid_t]) {
        lastDockActivity = Date()
        switcherPIDs = Set(pids.filter { $0 != 0 })
    }

    func clearSwitcherSession() {
        switcherPIDs = []
    }

    func shouldRefresh(pid: pid_t) -> Bool {
        guard pid != 0 else { return false }
        if !isIdle { lastDockActivity = Date() }
        if switcherPIDs.contains(pid) { return true }
        if currentHoveredPID == pid { return true }
        if let hoveredAt = recentHoveredAt[pid],
           Date().timeIntervalSince(hoveredAt) < Self.recentHoverTTL {
            return true
        }
        return false
    }

    func shouldMaintainWindowObserver(for pid: pid_t) -> Bool {
        shouldRefresh(pid: pid)
    }

    func pruneExpiredEntries() {
        let now = Date()
        recentHoveredAt = recentHoveredAt.filter {
            now.timeIntervalSince($0.value) < Self.recentHoverTTL
        }
    }
}
