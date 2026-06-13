import AppKit
import Core
import Foundation

/// CGS can only snapshot on-screen, non-minimized windows; minimized rows use disk cache only.
enum DockPreviewCaptureEligibility {
    static func canCapture(_ entry: DockPreviewWindowEntry) -> Bool {
        !entry.title.isEmpty && !entry.isMinimized && entry.isOnScreen
    }
}

/// DockDoor-aligned window enumeration + thumbnail capture with TTL skip (`WindowUtil` + `freshCachedWindowIDs`).
@MainActor
final class DockPreviewWindowCapturePipeline {
    /// Avoid burst-capturing huge window lists (e.g. Cursor with many minimized tabs).
    private static let maxCapturesPerHoverBatch = 8
    /// Global budget for one-shot live frames at launch (live preview off, disk still empty).
    private static let defaultLiveSnapshotSeedBudget = 12

    private var liveSnapshotSeedBudget = defaultLiveSnapshotSeedBudget
    private let cache: DockPreviewWindowCache
    private let diskStore: DockPreviewThumbnailDiskStore
    private let enumerator: any WindowEnumerating
    private let thumbnailService: any ThumbnailCapturing
    private var hubSettings: DockHubSettings
    private var previewsSettings: DockPreviewSettings
    private var lastGlobalWarmTime = Date.distantPast
    private let dockWorker: DockPreviewWorker?

    private static let globalWarmThrottleInterval: TimeInterval = 60

    init(
        cache: DockPreviewWindowCache,
        diskStore: DockPreviewThumbnailDiskStore,
        enumerator: any WindowEnumerating,
        thumbnailService: any ThumbnailCapturing,
        dockWorker: DockPreviewWorker? = nil,
        hubSettings: DockHubSettings = DockHubSettingsStore.load(),
        previewsSettings: DockPreviewSettings = DockHubSettingsStore.loadPreviews()
    ) {
        self.cache = cache
        self.diskStore = diskStore
        self.enumerator = enumerator
        self.thumbnailService = thumbnailService
        self.dockWorker = dockWorker
        self.hubSettings = hubSettings
        self.previewsSettings = previewsSettings
    }

    func reloadSettings(hub: DockHubSettings? = nil) {
        let loaded = hub ?? DockHubSettingsStore.load()
        hubSettings = loaded
        previewsSettings = loaded.previews
    }

    func resetLiveSnapshotSeedBudget() {
        liveSnapshotSeedBudget = Self.defaultLiveSnapshotSeedBudget
    }

    var cacheLifespan: TimeInterval {
        hubSettings.advanced.screenCaptureCacheLifespan
    }

    var processingDebounceInterval: TimeInterval {
        TimeInterval(hubSettings.advanced.windowProcessingDebounceMS) / 1000.0
    }

    func freshWindowIDs(pid: pid_t) -> Set<CGWindowID> {
        cache.freshWindowIDs(pid: pid, lifespan: cacheLifespan)
    }

    private func freshWindowIDsAsync(pid: pid_t) async -> Set<CGWindowID> {
        await cache.freshWindowIDsAsync(pid: pid, lifespan: cacheLifespan)
    }

    private func lookupFreshIDs(
        pid: pid_t,
        forceRefresh: Bool = false,
        freshIDs: Set<CGWindowID>? = nil
    ) async -> Set<CGWindowID> {
        if forceRefresh { return [] }
        if let freshIDs { return freshIDs }
        return await freshWindowIDsAsync(pid: pid)
    }

    /// True when every capturable on-screen window has a fresh on-disk thumbnail within `cacheLifespan`.
    func isDisplayCacheFresh(pid: pid_t) -> Bool {
        let cached = cache.readCached(pid: pid)
        let capturable = cached.filter(DockPreviewCaptureEligibility.canCapture)
        guard !capturable.isEmpty else {
            // Only minimized / off-screen rows — do not force refresh loops that cannot succeed.
            return !cached.filter { !$0.title.isEmpty }.isEmpty
        }
        let freshIDs = freshWindowIDs(pid: pid)
        return capturable.allSatisfy { freshIDs.contains($0.id) }
    }

    /// Skips full enumeration/capture when hover cache is already warm (DockDoor TTL path).
    func refreshAppIfNeeded(pid: pid_t, bundleIdentifier: String?, force: Bool = false) async {
        if !force, isDisplayCacheFresh(pid: pid) {
            let windows = cache.readCached(pid: pid).count
            DockPreviewThumbnailDiagnostics.refreshAppSkipped(
                pid: pid,
                bundleID: bundleIdentifier,
                windows: windows
            )
            return
        }
        await refreshApp(pid: pid, bundleIdentifier: bundleIdentifier)
    }

    /// Enumerates windows, updates cache, captures thumbnails (skipping fresh), purifies stale IDs, refreshes AX-only gaps.
    func refreshApp(pid: pid_t, bundleIdentifier: String?) async {
        guard pid != 0 else { return }
        let signpostID = PerformanceSignpost.DockCapture.beginRefreshApp(pid: pid)
        defer { PerformanceSignpost.DockCapture.endRefreshApp(signpostID) }
        let started = CFAbsoluteTimeGetCurrent()
        let entries: [DockPreviewWindowEntry]
        if let dockWorker {
            entries = await dockWorker.enumerateWindows(
                enumerator: enumerator,
                pid: pid,
                settings: previewsSettings,
                bundleIdentifier: bundleIdentifier,
                disableMinWindowSizeFilter: hubSettings.advanced.disableMinWindowSizeFilter
            )
        } else {
            entries = await enumerator.windows(
                for: pid,
                settings: previewsSettings,
                bundleIdentifier: bundleIdentifier,
                disableMinWindowSizeFilter: hubSettings.advanced.disableMinWindowSizeFilter
            )
        }
        _ = cache.update(entries: entries, for: pid)
        await purify(pid: pid)
        let cached = cache.readCached(pid: pid)
        let freshIDs = await freshWindowIDsAsync(pid: pid)
        let eligible = cached.filter { !$0.title.isEmpty }
        let skippedFresh = eligible.filter { freshIDs.contains($0.id) }.count
        await attachThumbnails(pid: pid, freshIDs: freshIDs)
        await refreshAXFallbackImages(pid: pid, freshIDs: freshIDs)
        await seedLiveSnapshotsForMissingThumbnails(pid: pid, freshIDs: freshIDs)
        let durationMs = Int((CFAbsoluteTimeGetCurrent() - started) * 1000)
        DockPreviewThumbnailDiagnostics.refreshApp(
            pid: pid,
            bundleID: bundleIdentifier,
            windows: cached.count,
            freshOnDisk: freshIDs.count,
            durationMs: durationMs,
            queued: max(0, eligible.count - skippedFresh),
            skippedFresh: skippedFresh
        )
    }

    /// DockDoor `updateAllWindowsInCurrentSpace` warm-up for all regular apps.
    func warmAllRunningApps(throttle: Bool = false) async {
        if throttle {
            let now = Date()
            guard now.timeIntervalSince(lastGlobalWarmTime) >= Self.globalWarmThrottleInterval else { return }
            lastGlobalWarmTime = now
        }
        let selfPID = ProcessInfo.processInfo.processIdentifier
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.processIdentifier != selfPID
        }
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        if let frontmostPID,
           let front = apps.first(where: { $0.processIdentifier == frontmostPID })
        {
            await refreshAppIfNeeded(
                pid: front.processIdentifier,
                bundleIdentifier: front.bundleIdentifier,
                force: false
            )
        }
        await withTaskGroup(of: Void.self) { group in
            for app in apps where app.processIdentifier != frontmostPID {
                group.addTask { [weak self] in
                    await self?.refreshAppIfNeeded(
                        pid: app.processIdentifier,
                        bundleIdentifier: app.bundleIdentifier
                    )
                }
            }
        }
        var pruned = 0
        if cacheLifespan > 0 {
            let cutoff = Date().addingTimeInterval(-cacheLifespan)
            pruned = await diskStore.pruneExpired(olderThan: cutoff)
        }
        DockPreviewThumbnailDiagnostics.warmComplete(
            appCount: apps.count,
            pruned: pruned,
            lifespanSec: cacheLifespan
        )
    }

    func removeCachedWindow(windowID: CGWindowID, pid: pid_t) {
        cache.removeFromCache(windowID: windowID, pid: pid)
    }

    /// When live preview is off, seed disk JPEGs via a short SC stream (one frame, then stop).
    func seedLiveSnapshotsForMissingThumbnails(
        pid: pid_t,
        maxCaptures: Int? = nil,
        freshIDs: Set<CGWindowID>? = nil
    ) async {
        guard !previewsSettings.enableLivePreview else { return }
        guard DockPreviewPermissionGate.screenRecordingGranted() else { return }

        let resolvedFreshIDs = await lookupFreshIDs(pid: pid, freshIDs: freshIDs)
        var missing: [DockPreviewWindowEntry] = []
        for entry in Self.prioritizedCaptureBatch(from: cache.readCached(pid: pid)) {
            guard !resolvedFreshIDs.contains(entry.id) else { continue }
            if await diskStore.loadIfPresentAsync(pid: pid, windowID: entry.id, title: entry.title) != nil {
                continue
            }
            missing.append(entry)
        }
        guard !missing.isEmpty else { return }

        var remaining = maxCaptures ?? liveSnapshotSeedBudget
        guard remaining > 0 else { return }

        for entry in missing {
            guard remaining > 0 else { break }
            guard let cgImage = await DockPreviewLiveSnapshotCapturer.capture(
                windowID: entry.id,
                hub: hubSettings
            ) else { continue }

            let capturedAt = Date()
            await diskStore.write(
                pid: pid,
                windowID: entry.id,
                cgImage: cgImage,
                capturedAt: capturedAt,
                title: entry.title
            )
            cache.recordThumbnailCaptured(windowID: entry.id, pid: pid, capturedAt: capturedAt)
            remaining -= 1
            if maxCaptures == nil {
                liveSnapshotSeedBudget = max(0, liveSnapshotSeedBudget - 1)
            }
        }
    }

    func attachThumbnails(pid: pid_t, forceRefresh: Bool = false, freshIDs: Set<CGWindowID>? = nil) async {
        guard DockPreviewPermissionGate.shouldCaptureWindowImages(hub: hubSettings) else { return }
        let resolvedFreshIDs = await lookupFreshIDs(
            pid: pid,
            forceRefresh: forceRefresh,
            freshIDs: freshIDs
        )
        let scale = CGFloat(max(1, hubSettings.advanced.windowPreviewImageScale))
        let quality = hubSettings.advanced.windowImageCaptureQuality
        let entries = cache.readCached(pid: pid)
        let eligible = Self.prioritizedCaptureBatch(from: entries)
        let skippedFresh = eligible.filter { resolvedFreshIDs.contains($0.id) }.count
        DockPreviewThumbnailDiagnostics.attachBatch(
            pid: pid,
            total: eligible.count,
            skippedFresh: skippedFresh,
            queued: eligible.count - skippedFresh,
            forceRefresh: forceRefresh
        )
        await withTaskGroup(of: Void.self) { group in
            for entry in eligible {
                if resolvedFreshIDs.contains(entry.id) { continue }
                group.addTask { [weak self] in
                    await self?.captureThumbnail(
                        windowID: entry.id,
                        pid: pid,
                        scale: scale,
                        quality: quality,
                        freshIDs: resolvedFreshIDs
                    )
                }
            }
        }
    }

    /// Drops stale rows (CGWindowList + helper-owner windows that do not belong to the display app).
    func purify(pid: pid_t) async {
        guard let app = NSRunningApplication(processIdentifier: pid) else {
            cache.clear(pid: pid)
            return
        }
        let cgList = copyCGWindowList()
        let liveIDs = Set(windowIDsFromCGList(cgList, matching: { ownerPID, _ in ownerPID == app.processIdentifier }))
        let helperOwnerIDs = Set(windowIDsFromCGList(cgList, matching: { ownerPID, _ in
            guard let owner = NSRunningApplication(processIdentifier: ownerPID) else { return false }
            return DockPreviewWindowOwnerResolver.ownerBelongsToDisplayApp(owner, displayApp: app)
                && owner.processIdentifier != app.processIdentifier
        }))
        for entry in cache.readCached(pid: pid) {
            if !liveIDs.contains(entry.id), !helperOwnerIDs.contains(entry.id) {
                cache.removeFromCache(windowID: entry.id, pid: pid)
            }
        }
    }

    /// Capture thumbnails for entries still missing on-disk images after enumeration (AX-only gaps).
    func refreshAXFallbackImages(pid: pid_t, freshIDs: Set<CGWindowID>? = nil) async {
        guard DockPreviewPermissionGate.shouldCaptureWindowImages(hub: hubSettings) else { return }
        let resolvedFreshIDs = await lookupFreshIDs(pid: pid, freshIDs: freshIDs)
        let missing = cache.readCached(pid: pid).filter { entry in
            DockPreviewCaptureEligibility.canCapture(entry)
                && !resolvedFreshIDs.contains(entry.id)
        }
        guard !missing.isEmpty else { return }
        let scale = CGFloat(max(1, hubSettings.advanced.windowPreviewImageScale))
        let quality = hubSettings.advanced.windowImageCaptureQuality
        await withTaskGroup(of: Void.self) { group in
            for entry in missing {
                group.addTask { [weak self] in
                    await self?.captureThumbnail(
                        windowID: entry.id,
                        pid: pid,
                        scale: scale,
                        quality: quality,
                        forceRefresh: true,
                        freshIDs: resolvedFreshIDs
                    )
                }
            }
        }
    }

    private func captureThumbnail(
        windowID: CGWindowID,
        pid: pid_t,
        scale: CGFloat,
        quality: DockWindowImageCaptureQuality,
        forceRefresh: Bool = false,
        freshIDs: Set<CGWindowID>? = nil
    ) async {
        if !forceRefresh {
            let resolvedFreshIDs = await lookupFreshIDs(pid: pid, freshIDs: freshIDs)
            if resolvedFreshIDs.contains(windowID) {
                DockPreviewThumbnailDiagnostics.captureSkipFresh(pid: pid, windowID: windowID)
                return
            }
        }
        guard let image = await thumbnailService.capture(windowID: windowID, scale: scale, quality: quality) else {
            DockPreviewThumbnailDiagnostics.captureFailed(pid: pid, windowID: windowID, reason: "cgsNil")
            return
        }
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            DockPreviewThumbnailDiagnostics.captureFailed(pid: pid, windowID: windowID, reason: "cgImageNil")
            return
        }
        let capturedAt = Date()
        let title = cache.readCached(pid: pid).first(where: { $0.id == windowID })?.title
        await diskStore.write(
            pid: pid,
            windowID: windowID,
            cgImage: cgImage,
            capturedAt: capturedAt,
            title: title
        )
        cache.recordThumbnailCaptured(windowID: windowID, pid: pid, capturedAt: capturedAt)
        DockPreviewThumbnailDiagnostics.captureStored(
            pid: pid,
            windowID: windowID,
            width: cgImage.width,
            height: cgImage.height
        )
    }

    private static func prioritizedCaptureBatch(from entries: [DockPreviewWindowEntry]) -> [DockPreviewWindowEntry] {
        let capturable = entries
            .filter(DockPreviewCaptureEligibility.canCapture)
            .sorted { lhs, rhs in
                let lhsArea = lhs.frame.width * lhs.frame.height
                let rhsArea = rhs.frame.width * rhs.frame.height
                return lhsArea > rhsArea
            }
        return Array(capturable.prefix(maxCapturesPerHoverBatch))
    }

    private func copyCGWindowList() -> [[String: AnyObject]] {
        let options: CGWindowListOption = [.optionAll, .excludeDesktopElements]
        return (CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: AnyObject]]) ?? []
    }

    private func windowIDsFromCGList(
        _ list: [[String: AnyObject]],
        matching predicate: (pid_t, [String: AnyObject]) -> Bool
    ) -> [CGWindowID] {
        list.compactMap { info -> CGWindowID? in
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? Int32,
                  predicate(ownerPID, info),
                  let windowID = info[kCGWindowNumber as String] as? UInt32
            else { return nil }
            return CGWindowID(windowID)
        }
    }
}
