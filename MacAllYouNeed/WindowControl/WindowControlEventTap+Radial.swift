import AppKit
import ApplicationServices
import Core
import Platform

// Radial-menu trigger handling for the window event tap. Extracted from
// `WindowControlEventTap` to keep that file focused on the drag/snap gestures.
extension WindowControlEventTap {
    /// Phases of the radial-menu gesture, emitted to `radialPhaseHandler`.
    enum RadialPhase: Equatable {
        case open(center: CGPoint)
        case update(cursor: CGPoint)
        case commit
        case cancel
    }

    /// Builds the CGEvent mask. Radial keys (`flagsChanged` + `mouseMoved`) are
    /// only included when the radial menu is enabled, so the tap does not see
    /// pointer/modifier traffic it would otherwise ignore.
    func eventMask(includeRadialKeys: Bool) -> CGEventMask {
        let mouseMask = CGEventMask(1 << CGEventType.leftMouseDown.rawValue)
            | CGEventMask(1 << CGEventType.leftMouseDragged.rawValue)
            | CGEventMask(1 << CGEventType.leftMouseUp.rawValue)
            | CGEventMask(1 << CGEventType.rightMouseDown.rawValue)
            | CGEventMask(1 << CGEventType.rightMouseDragged.rawValue)
            | CGEventMask(1 << CGEventType.rightMouseUp.rawValue)
        let recoveryMask = CGEventMask(1 << CGEventType.tapDisabledByTimeout.rawValue)
            | CGEventMask(1 << CGEventType.tapDisabledByUserInput.rawValue)
        var mask = mouseMask | recoveryMask
        if includeRadialKeys {
            mask |= CGEventMask(1 << CGEventType.flagsChanged.rawValue)
            mask |= CGEventMask(1 << CGEventType.mouseMoved.rawValue)
        }
        return mask
    }

    /// Reconciles the tap mask when `radialMenuEnabled` flips. The mask can only
    /// be set at creation, so we stop and let the caller restart via `start()`.
    func updateRuntime(radialMenuEnabled: Bool) {
        guard isRunning else { return }
        guard radialKeysInstalled != radialMenuEnabled else { return }
        stop()
    }

    /// Pure decision: given the radial-active state and the modifier flags,
    /// returns the resulting phase. Exact-match on the trigger modifier so the
    /// radial menu does not arm when extra modifiers (e.g. Command) are held.
    static func radialPhase(
        active: Bool,
        type: CGEventType,
        flags: CGEventFlags,
        location: CGPoint,
        triggerModifier: WindowGestureModifier
    ) -> RadialPhase? {
        let modifiers = WindowGestureModifier(cgEventFlags: flags)
        let triggerHeld = modifiers.radialExactMatch(triggerModifier)
        switch type {
        case .flagsChanged:
            // Tap-to-open: first press opens. Releasing the modifier does NOT commit
            // (the menu stays open). The user clicks to apply or presses Esc to cancel.
            if triggerHeld, !active {
                return .open(center: location)
            }
            return nil
        case .mouseMoved:
            return active ? .update(cursor: location) : nil
        default:
            return nil
        }
    }

    /// Applies the radial phase decision and drives the handler. Returns `true`
    /// when the event was consumed by the radial menu.
    func handleRadialEvent(type: CGEventType, flags: CGEventFlags, location: CGPoint) -> Bool {
        guard let phase = Self.radialPhase(
            active: radialActive,
            type: type,
            flags: flags,
            location: location,
            triggerModifier: radialTriggerModifier
        ) else {
            return false
        }
        switch phase {
        case .open:
            radialActive = true
        case .update:
            break
        case .commit, .cancel:
            radialActive = false
        }
        if let radialPhaseHandler {
            Task { @MainActor in radialPhaseHandler(phase) }
        }
        // flagsChanged must pass through so other apps still see modifier state;
        // only mouseMoved updates are swallowed while the menu is open.
        return type == .mouseMoved
    }
}

extension WindowGestureModifier {
    /// Logical primary modifiers (option/control/command/shift), folding the
    /// left/right hardware variants into their base flag.
    fileprivate static let radialPrimaryMask: WindowGestureModifier = [.option, .control, .command, .shift]

    /// Exact match comparing only normalized primary modifiers on both sides so
    /// that left/right variants (e.g. .leftControl) resolve correctly against
    /// generic stored values (e.g. .control) and vice-versa.
    func radialExactMatch(_ target: WindowGestureModifier) -> Bool {
        normalizedPrimary == target.normalizedPrimary
    }

    var normalizedPrimary: WindowGestureModifier {
        var result: WindowGestureModifier = []
        if contains(.option) || contains(.leftOption) || contains(.rightOption) { result.insert(.option) }
        if contains(.control) || contains(.leftControl) || contains(.rightControl) { result.insert(.control) }
        if contains(.command) || contains(.leftCommand) || contains(.rightCommand) { result.insert(.command) }
        if contains(.shift) || contains(.leftShift) || contains(.rightShift) { result.insert(.shift) }
        return result
    }
}
