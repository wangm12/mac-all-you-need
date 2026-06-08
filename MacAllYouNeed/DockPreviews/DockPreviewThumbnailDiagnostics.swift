import AppKit
import Foundation

/// Structured worklog events for disk-backed dock preview thumbnails (`enableWorklog` in Dock settings).
enum DockPreviewThumbnailDiagnostics {
    // MARK: - Disk store

    static func diskWrite(
        pid: pid_t,
        windowID: CGWindowID,
        width: Int,
        height: Int,
        fileBytes: Int?,
        ok: Bool
    ) {
        var fields: [String: CustomStringConvertible] = [
            "pid": pid,
            "windowID": windowID,
            "w": width,
            "h": height,
            "ok": ok,
        ]
        if let fileBytes { fields["bytes"] = fileBytes }
        log("disk.write", fields: fields)
    }

    static func diskLoad(pid: pid_t, windowID: CGWindowID, hit: Bool, fileBytes: Int? = nil) {
        var fields: [String: CustomStringConvertible] = [
            "pid": pid,
            "windowID": windowID,
            "hit": hit,
        ]
        if let fileBytes { fields["bytes"] = fileBytes }
        log("disk.load", fields: fields)
    }

    static func diskRemove(pid: pid_t, windowID: CGWindowID? = nil, scope: String) {
        var fields: [String: CustomStringConvertible] = ["pid": pid, "scope": scope]
        if let windowID { fields["windowID"] = windowID }
        log("disk.remove", fields: fields)
    }

    static func diskPrune(removed: Int, cutoff: Date) {
        log("disk.prune", fields: [
            "removed": removed,
            "cutoff": iso8601(cutoff),
        ])
    }

    static func diskInventory(pidDirs: Int, files: Int, bytes: Int, root: String) {
        log("disk.inventory", fields: [
            "pidDirs": pidDirs,
            "files": files,
            "bytes": bytes,
            "root": root,
        ])
    }

    // MARK: - Visible LRU

    static func lruHydrate(
        entries: Int,
        lruHits: Int,
        diskLoads: Int,
        misses: Int,
        resident: Int
    ) {
        log("lru.hydrate", fields: [
            "entries": entries,
            "lruHits": lruHits,
            "diskLoads": diskLoads,
            "misses": misses,
            "resident": resident,
        ])
    }

    static func lruEvict(residentBefore: Int) {
        log("lru.evict", fields: ["resident": residentBefore])
    }

    // MARK: - Capture pipeline

    static func captureSkipFresh(pid: pid_t, windowID: CGWindowID) {
        log("capture.skipFresh", fields: ["pid": pid, "windowID": windowID])
    }

    static func captureFailed(pid: pid_t, windowID: CGWindowID, reason: String) {
        log("capture.failed", fields: ["pid": pid, "windowID": windowID, "reason": reason])
    }

    static func captureStored(pid: pid_t, windowID: CGWindowID, width: Int, height: Int) {
        log("capture.stored", fields: [
            "pid": pid,
            "windowID": windowID,
            "w": width,
            "h": height,
        ])
    }

    static func attachBatch(
        pid: pid_t,
        total: Int,
        skippedFresh: Int,
        queued: Int,
        forceRefresh: Bool
    ) {
        log("capture.attachBatch", fields: [
            "pid": pid,
            "total": total,
            "skippedFresh": skippedFresh,
            "queued": queued,
            "forceRefresh": forceRefresh,
        ])
    }

    static func refreshApp(
        pid: pid_t,
        bundleID: String?,
        windows: Int,
        freshOnDisk: Int,
        durationMs: Int,
        queued: Int,
        skippedFresh: Int
    ) {
        log("capture.refreshApp", fields: [
            "pid": pid,
            "bundleID": bundleID ?? "",
            "windows": windows,
            "freshOnDisk": freshOnDisk,
            "durationMs": durationMs,
            "queued": queued,
            "skippedFresh": skippedFresh,
        ])
    }

    static func refreshAppSkipped(pid: pid_t, bundleID: String?, windows: Int) {
        log("capture.refreshAppSkipped", fields: [
            "pid": pid,
            "bundleID": bundleID ?? "",
            "windows": windows,
        ])
    }

    static func warmComplete(appCount: Int, pruned: Int, lifespanSec: TimeInterval) {
        log("capture.warmComplete", fields: [
            "apps": appCount,
            "pruned": pruned,
            "lifespanSec": lifespanSec,
        ])
    }

    // MARK: - Internals

    private static func log(_ event: String, fields: [String: CustomStringConvertible]) {
        guard DockPreviewWorklog.isEnabled else { return }
        DockPreviewWorklog.log("thumb.\(event)", fields: fields)
    }

    private static func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    static func jpegFileBytes(at url: URL) -> Int? {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize)
    }
}
