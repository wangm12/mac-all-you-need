import AppKit

/// RAII wrapper around `NSEvent.addLocalMonitorForEvents` / `addGlobalMonitorForEvents`.
/// Removes the underlying monitor automatically in `deinit`, so callers cannot
/// leak a monitor by forgetting to call `removeMonitor`.
public final class NSEventMonitorHandle {
    private var token: Any?

    /// Installs a local monitor. The handler can return nil to swallow the
    /// event or pass it through.
    public init(local matching: NSEvent.EventTypeMask, handler: @escaping (NSEvent) -> NSEvent?) {
        token = NSEvent.addLocalMonitorForEvents(matching: matching, handler: handler)
    }

    /// Installs a global monitor. Global monitors observe events delivered to
    /// other applications; the handler cannot swallow events.
    public init(global matching: NSEvent.EventTypeMask, handler: @escaping (NSEvent) -> Void) {
        token = NSEvent.addGlobalMonitorForEvents(matching: matching, handler: handler)
    }

    deinit {
        if let token { NSEvent.removeMonitor(token) }
    }
}
