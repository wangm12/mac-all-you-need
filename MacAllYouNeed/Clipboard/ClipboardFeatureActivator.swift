import FeatureCore
import Foundation

/// Owns the Clipboard feature's enable/disable lifecycle state.
///
/// Runtime start/stop (snippet expander, reader polling, dock, hotkeys) is handled
/// by `AppController.refreshClipboardFeatureAvailability()`. This activator tracks
/// logical state for `FeatureRuntime`.
public actor ClipboardFeatureActivator: FeatureActivator {
    private var _isPolling: Bool = false
    private let testMode: Bool

    /// True while the clipboard feature is logically active.
    public var isPolling: Bool { _isPolling }

    public init(testMode: Bool = false) {
        self.testMode = testMode
    }

    public func activate() async throws {
        guard !_isPolling else { return }   // idempotent
        _isPolling = true
    }

    public func deactivate() async throws {
        guard _isPolling else { return }   // idempotent
        _isPolling = false
    }
}
