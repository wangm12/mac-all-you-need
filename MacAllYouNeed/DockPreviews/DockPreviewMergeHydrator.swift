import Foundation

/// Handles thumbnail merge and async disk hydration for DockPreviewCoordinator.
///
/// Owns the generation counter that prevents stale async disk hydrates
/// from repainting the wrong hover, and provides the static utility for
/// deciding whether a hydration pass produced meaningful thumbnail changes.
@MainActor
final class DockPreviewMergeHydrator {

    // MARK: - Callbacks into coordinator

    var onApplyMergePanel: ((_ pid: pid_t, _ list: [DockPreviewWindowEntry], _ reposition: Bool, _ allowEmpty: Bool) -> Void)?
    var hydrateAsync: ((_ entries: [DockPreviewWindowEntry]) async -> [DockPreviewWindowEntry])?
    var hydrateSync: ((_ entries: [DockPreviewWindowEntry]) -> [DockPreviewWindowEntry])?
    var currentPID: () -> pid_t? = { nil }
    var currentHoverIsApp: () -> Bool = { false }

    // MARK: - Generation counter

    /// Bumps on each `merge` call so stale async disk hydrates cannot repaint
    /// the wrong hover.
    private var generation: UInt64 = 0

    func bumpGeneration() {
        generation &+= 1
    }

    // MARK: - Merge

    func merge(
        pid: pid_t,
        raw: [DockPreviewWindowEntry],
        reposition: Bool,
        allowEmpty: Bool
    ) {
        generation &+= 1
        let gen = generation

        // Paint immediately from LRU / in-memory thumbnails so hover does not wait on disk I/O.
        let quickList = hydrateSync?(raw) ?? raw
        onApplyMergePanel?(pid, quickList, reposition, allowEmpty)

        Task { @MainActor [weak self] in
            guard let self else { return }
            guard gen == self.generation else { return }
            guard self.currentPID() == pid, self.currentHoverIsApp() else { return }
            let hydrated = await self.hydrateAsync?(raw) ?? raw
            guard gen == self.generation else { return }
            guard self.currentPID() == pid, self.currentHoverIsApp() else { return }
            guard Self.entriesNeedThumbnailRefresh(quickList, hydrated) else { return }
            self.onApplyMergePanel?(pid, hydrated, false, allowEmpty)
        }
    }

    // MARK: - Static utility

    static func entriesNeedThumbnailRefresh(
        _ before: [DockPreviewWindowEntry],
        _ after: [DockPreviewWindowEntry]
    ) -> Bool {
        guard before.count == after.count else { return true }
        for (lhs, rhs) in zip(before, after) {
            if lhs.id != rhs.id { return true }
            let hadThumb = lhs.thumbnail != nil
            let hasThumb = rhs.thumbnail != nil
            if hadThumb != hasThumb { return true }
        }
        return false
    }
}
