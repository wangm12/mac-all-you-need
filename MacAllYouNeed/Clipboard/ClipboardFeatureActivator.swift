import FeatureCore
import Foundation

/// Owns the Clipboard feature's enable/disable lifecycle state.
///
/// The clipboard subsystem (LocalClipboardReader, SnippetExpander, hotkeys)
/// is wired by AppController at launch and runs continuously while the app is
/// open; it does not start or stop per feature-enable toggle. This activator
/// therefore only tracks the logical enabled/disabled state so the FeatureRuntime
/// can reflect it. testMode=true lets unit tests exercise the state machine
/// without requiring Accessibility permission or a live database.
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
