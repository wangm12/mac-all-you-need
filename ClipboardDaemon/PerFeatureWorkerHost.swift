import FeatureCore
import Foundation
import Platform

/// Manages per-feature daemon-side workers with idempotent start/stop.
///
/// Currently only `.clipboard` has daemon-side workers:
/// - `PasteboardObserver` — polls NSPasteboard for changes.
/// Snippet expansion runs in the main app (needs its Accessibility permission).
///
/// `.downloader`, `.folderPreview`, `.voice`, `.windowLayouts`, and `.windowGrab`
/// have no daemon-side workers (the DispatchServer and Window Control live in the main app).
final class PerFeatureWorkerHost {
    private let observer: PasteboardObserver
    /// Called when the pasteboard observer detects a change.
    /// Must be set before `startWorkers(for: .clipboard)` is called.
    var onPasteboardChange: ((PasteboardChange) -> Void)?

    private var clipboardRunning = false

    init(observer: PasteboardObserver) {
        self.observer = observer
    }

    /// Idempotent. Starts workers for the given feature if not already running.
    func startWorkers(for id: FeatureID) {
        switch id {
        case .clipboard:
            guard !clipboardRunning else { return }
            if let cb = onPasteboardChange {
                observer.start(callback: cb)
            }
            clipboardRunning = true
        case .downloader, .folderPreview, .voice, .windowLayouts, .windowGrab,
             .clipboardSmartText, .folderHistory, .voiceReminders, .aiFileOrganizer, .dockPreviews:
            break // no daemon-side workers for these features
        }
    }

    /// Idempotent. Stops workers for the given feature if currently running.
    func stopWorkers(for id: FeatureID) {
        switch id {
        case .clipboard:
            guard clipboardRunning else { return }
            observer.stop()
            clipboardRunning = false
        case .downloader, .folderPreview, .voice, .windowLayouts, .windowGrab,
             .clipboardSmartText, .folderHistory, .voiceReminders, .aiFileOrganizer, .dockPreviews:
            break
        }
    }

    /// Applies a diff from `FeatureStateDarwinObserver.onChange`.
    func apply(diff: [FeatureID: ActivationState]) {
        for (id, state) in diff {
            switch state {
            case .enabled:
                startWorkers(for: id)
            case .disabled:
                stopWorkers(for: id)
            }
        }
    }

    /// Re-starts the clipboard pasteboard observer if it is already marked as running.
    ///
    /// Call this after `onPasteboardChange` has been set and the observer was started
    /// without a callback (because the clipboard feature was enabled at init time but
    /// `onPasteboardChange` was not yet wired up). No-op if clipboard is not running.
    func restartClipboardObserverIfRunning() {
        guard clipboardRunning, let cb = onPasteboardChange else { return }
        observer.stop()
        observer.start(callback: cb)
    }

    /// Stops all running workers. Called on daemon teardown.
    func stopAllWorkers() {
        stopWorkers(for: .clipboard)
    }
}
