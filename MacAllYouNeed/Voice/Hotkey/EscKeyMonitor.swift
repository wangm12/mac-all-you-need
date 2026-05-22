import AppKit
import Platform

/// Owns the global + local `NSEvent.keyDown` monitors that listen for Esc,
/// Return, or numpad Enter while voice dictation may be in flight.
///
/// Replaces the inline monitor setup that used to live in
/// `VoiceCoordinator.installEscKeyMonitor()`. Splitting it out makes the
/// dispatch path testable (call `handle(event:)` directly) without having to
/// post synthetic NSEvents through the AppKit run loop.
///
/// Lifetime: the monitor self-removes via `NSEventMonitorHandle`'s RAII
/// behaviour when this object is released.
@MainActor
final class EscKeyMonitor {
    /// macOS virtual key codes for the three keys we react to.
    enum KeyCode {
        static let escape: UInt16 = 0x35
        static let `return`: UInt16 = 0x24
        static let numpadEnter: UInt16 = 0x4C
    }

    /// Fired when the Esc key is pressed.
    var onEsc: (() -> Void)?
    /// Fired when Return or numpad Enter is pressed.
    var onReturn: (() -> Void)?

    private var globalMonitor: NSEventMonitorHandle?
    private var localMonitor: NSEventMonitorHandle?

    init(onEsc: (() -> Void)? = nil, onReturn: (() -> Void)? = nil) {
        self.onEsc = onEsc
        self.onReturn = onReturn
    }

    deinit {
        // NSEventMonitorHandle removes its own NSEvent monitor token in deinit.
    }

    /// Installs the global + local monitors. No-op if already installed.
    func install() {
        if globalMonitor != nil || localMonitor != nil { return }
        let dispatcher: @Sendable (NSEvent) -> Void = { [weak self] event in
            Task { @MainActor in self?.handle(event: event) }
        }
        // Global: events while another app has focus. Common case for our
        // non-activating HUD panel.
        globalMonitor = NSEventMonitorHandle(global: .keyDown) { event in
            dispatcher(event)
        }
        // Local: events while our app is active. Return the event so we react
        // without swallowing it — other handlers still receive it.
        localMonitor = NSEventMonitorHandle(local: .keyDown) { event in
            dispatcher(event)
            return event
        }
    }

    /// Drop both monitors. Safe to call multiple times.
    func uninstall() {
        globalMonitor = nil
        localMonitor = nil
    }

    /// Test-friendly entry point — call directly with an NSEvent (or
    /// equivalent) to exercise dispatch without posting events through
    /// AppKit. Production code goes through the global/local monitor handlers
    /// installed in `install()`, which deduplicate by sharing the same
    /// `handle(event:)` body.
    func handle(event: NSEvent) {
        let keyCode = event.keyCode
        guard keyCode == KeyCode.escape
            || keyCode == KeyCode.return
            || keyCode == KeyCode.numpadEnter
        else { return }
        switch keyCode {
        case KeyCode.escape:
            onEsc?()
        case KeyCode.return, KeyCode.numpadEnter:
            onReturn?()
        default:
            break
        }
    }
}
