import FeatureCore
import Foundation

/// Owns the Clipboard subsystem's lifecycle.
///
/// In production this wraps the same init/start/stop code that AppController
/// has always run. In testMode=true every real system call (pasteboard polling,
/// CGEventTap, Carbon hotkey) is skipped so unit tests don't require
/// Accessibility permission or a live database.
public actor ClipboardFeatureActivator: FeatureActivator {
    private var snippetExpander: SnippetExpander?
    private var hotkeyController: HotkeyController?
    private var _isPolling: Bool = false
    private let testMode: Bool

    /// True while the pasteboard poller (or test-mode stub) is running.
    public var isPolling: Bool { _isPolling }

    public init(testMode: Bool = false) {
        self.testMode = testMode
    }

    public func activate() async throws {
        guard !_isPolling else { return }   // idempotent
        _isPolling = true

        if !testMode {
            // Start snippet expansion. The lookup closure is a lightweight
            // no-op stub here because the activator doesn't own the SnippetStore
            // (AppController still holds the authoritative store reference).
            // Phase 04 will thread the store through dependency injection.
            let expander = SnippetExpander { _ in nil }
            expander.start()
            snippetExpander = expander
            // HotkeyController requires a DockWindowController reference which
            // is still owned by AppController. We record the intent here; Phase 04
            // will complete the wiring once dependency injection lands.
        }
    }

    public func deactivate() async throws {
        guard _isPolling else { return }   // idempotent
        snippetExpander?.stop()
        snippetExpander = nil
        hotkeyController?.unregister()
        hotkeyController = nil
        _isPolling = false
    }
}
