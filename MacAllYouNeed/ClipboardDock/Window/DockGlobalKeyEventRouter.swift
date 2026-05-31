import AppKit
import ApplicationServices
import Foundation
import Platform

/// Fallback action that the dock takes when a key event arrives while the
/// dock is visible but not the key window (NSEvent global monitor can't
/// swallow, so we use a CGEventTap as a secondary path for the same set
/// of bindings).
enum DockGlobalKeyFallbackAction: Equatable {
    case quickLook
    case dismiss
    case focusBackward
    case focusForward
}

/// Bindings used by the global fallback path. `quickLook` / `dismiss` are
/// the user-configurable shortcut bindings; left/right arrows are hardcoded.
struct DockGlobalKeyFallbackBindings {
    let quickLook: [HotkeyDescriptor]
    let dismiss: [HotkeyDescriptor]
}

/// Pure-function mapper from (keyCode, modifierMask) -> fallback action.
enum DockGlobalKeyFallbackPolicy {
    static func modifierMask(from flags: CGEventFlags) -> UInt {
        var modifiers: NSEvent.ModifierFlags = []
        if flags.contains(.maskAlphaShift) { modifiers.insert(.capsLock) }
        if flags.contains(.maskShift) { modifiers.insert(.shift) }
        if flags.contains(.maskControl) { modifiers.insert(.control) }
        if flags.contains(.maskAlternate) { modifiers.insert(.option) }
        if flags.contains(.maskCommand) { modifiers.insert(.command) }
        return modifiers.rawValue & NSEvent.ModifierFlags.deviceIndependentFlagsMask.rawValue
    }

    static func action(
        keyCode: UInt16,
        modifierMask: UInt,
        bindings: DockGlobalKeyFallbackBindings
    ) -> DockGlobalKeyFallbackAction? {
        if matches(bindings.quickLook, keyCode: keyCode, modifierMask: modifierMask) {
            return .quickLook
        }
        if matches(bindings.dismiss, keyCode: keyCode, modifierMask: modifierMask) {
            return .dismiss
        }

        guard modifierMask == 0 else { return nil }
        switch keyCode {
        case 123:
            return .focusBackward
        case 124:
            return .focusForward
        default:
            return nil
        }
    }

    private static func matches(
        _ bindings: [HotkeyDescriptor],
        keyCode: UInt16,
        modifierMask: UInt
    ) -> Bool {
        bindings.contains { $0.matches(keyCode: keyCode, modifierMask: modifierMask) }
    }
}

/// Owns the CGEventTap installed alongside the dock's NSEvent global key
/// monitor. The two monitors duplicate-fire for the same fallback bindings —
/// the NSEvent monitor never swallows events (global monitors can't), so the
/// CGEventTap is the path that suppresses propagation.
private final class DockGlobalKeyEventTap {
    private let bindings: DockGlobalKeyFallbackBindings
    private let handleAction: @MainActor (DockGlobalKeyFallbackAction) -> Void
    private var tapController: CGEventTapController?

    init(
        bindings: DockGlobalKeyFallbackBindings,
        handleAction: @escaping @MainActor (DockGlobalKeyFallbackAction) -> Void
    ) {
        self.bindings = bindings
        self.handleAction = handleAction
    }

    @discardableResult
    func start() -> Bool {
        guard tapController == nil else { return true }

        let eventMask = CGEventMask(1 << CGEventType.keyDown.rawValue)
            | CGEventMask(1 << CGEventType.tapDisabledByTimeout.rawValue)
            | CGEventMask(1 << CGEventType.tapDisabledByUserInput.rawValue)
        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        let controller = CGEventTapController(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            runLoop: .main,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let eventTap = Unmanaged<DockGlobalKeyEventTap>.fromOpaque(userInfo).takeUnretainedValue()
                return eventTap.handle(type: type, event: event)
            },
            userInfo: userInfo
        )
        do {
            try controller.install()
        } catch {
            return false
        }
        controller.enable()
        tapController = controller
        return true
    }

    func stop() {
        tapController?.uninstall()
        tapController = nil
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            tapController?.reenableAfterTimeout()
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let modifierMask = DockGlobalKeyFallbackPolicy.modifierMask(from: event.flags)
        guard let action = DockGlobalKeyFallbackPolicy.action(
            keyCode: keyCode,
            modifierMask: modifierMask,
            bindings: bindings
        ) else {
            return Unmanaged.passUnretained(event)
        }

        Task { @MainActor [handleAction] in
            handleAction(action)
        }
        return nil
    }
}

/// Coordinates the dock's global-key event handling. Wires together:
///   1. an `NSEvent` global keyDown monitor (sees the event but can't swallow),
///   2. a `DockGlobalKeyEventTap` CGEventTap (swallows, but needs Accessibility).
///
/// Both paths funnel through `DockGlobalKeyFallbackPolicy.action(...)`, so a
/// single set of bindings produces consistent behavior. The router also
/// exposes `route(...)` so a caller can dispatch an arbitrary NSEvent (used
/// by the existing test surface and the local monitor's fallback path).
@MainActor
final class DockGlobalKeyEventRouter {
    private let bindingsProvider: () -> DockGlobalKeyFallbackBindings
    private let handleAction: (DockGlobalKeyFallbackAction) -> Void

    private var nsEventMonitor: NSEventMonitorHandle?
    private var eventTap: DockGlobalKeyEventTap?

    init(
        bindingsProvider: @escaping () -> DockGlobalKeyFallbackBindings,
        handleAction: @escaping (DockGlobalKeyFallbackAction) -> Void
    ) {
        self.bindingsProvider = bindingsProvider
        self.handleAction = handleAction
    }

    /// Pure routing: given an NSEvent + bindings, return the action (or nil).
    /// Side-effect free — used by the local monitor's global-fallback bridge
    /// and by unit tests.
    nonisolated static func route(
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags,
        bindings: DockGlobalKeyFallbackBindings
    ) -> DockGlobalKeyFallbackAction? {
        let modifierMask = modifierFlags.rawValue
            & NSEvent.ModifierFlags.deviceIndependentFlagsMask.rawValue
        return DockGlobalKeyFallbackPolicy.action(
            keyCode: keyCode,
            modifierMask: modifierMask,
            bindings: bindings
        )
    }

    /// Install both the NSEvent global monitor and the CGEventTap. Idempotent.
    func start() {
        stop()
        let handleAction = handleAction
        nsEventMonitor = NSEventMonitorHandle(global: .keyDown) { [weak self] event in
            Task { @MainActor in
                guard let self else { return }
                let bindings = self.bindingsProvider()
                guard let action = DockGlobalKeyEventRouter.route(
                    keyCode: event.keyCode,
                    modifierFlags: event.modifierFlags,
                    bindings: bindings
                ) else { return }
                self.handleAction(action)
            }
        }

        let tap = DockGlobalKeyEventTap(bindings: bindingsProvider()) { action in
            handleAction(action)
        }
        if tap.start() {
            eventTap = tap
        }
    }

    /// Tear down both monitors. Safe to call repeatedly.
    func stop() {
        nsEventMonitor = nil
        eventTap?.stop()
        eventTap = nil
    }
}
