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
        case selectAction(WindowAction)
        case commit
        case cancel
    }

    fileprivate static let radialMultiTapWindow: TimeInterval = ModifierTapTiming.multiTapWindow

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
            mask |= CGEventMask(1 << CGEventType.keyDown.rawValue)
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
        triggerModifier: WindowGestureModifier,
        triggerTapCount: Int = 1
    ) -> RadialPhase? {
        let modifiers = WindowGestureModifier(cgEventFlags: flags)
        let triggerHeld = modifiers.radialExactMatch(triggerModifier)
        switch type {
        case .flagsChanged:
            if triggerTapCount > 1,
               let tapKey = triggerModifier.radialSingleTapKey,
               triggerTapCount == 2 {
                // Double-tap path is handled in `handleRadialDoubleTapEvent`.
                _ = tapKey
                return nil
            }
            if triggerHeld, !active {
                return .open(center: location)
            }
            if active, !triggerHeld {
                return .commit
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
        let tapCount = radialTriggerTapCount
        if tapCount > 1, radialTriggerModifier.radialSingleTapKey != nil {
            return handleRadialDoubleTapEvent(type: type, flags: flags, location: location)
        }

        guard let phase = Self.radialPhase(
            active: radialActive,
            type: type,
            flags: flags,
            location: location,
            triggerModifier: radialTriggerModifier,
            triggerTapCount: tapCount
        ) else {
            return false
        }
        return emitRadialPhase(phase, type: type)
    }

    private func handleRadialDoubleTapEvent(type: CGEventType, flags: CGEventFlags, location: CGPoint) -> Bool {
        guard let tapKey = radialTriggerModifier.radialSingleTapKey else {
            return false
        }
        let modifiers = WindowGestureModifier(cgEventFlags: flags)
        let triggerHeld = modifiers.radialExactMatch(radialTriggerModifier)
        let now = ProcessInfo.processInfo.systemUptime

        switch type {
        case .flagsChanged:
            if triggerHeld, !radialTriggerWasHeld, !radialActive {
                radialComboChordActive = false
                if let last = radialTapLastRelease,
                   last.key == tapKey,
                   now - last.time <= Self.radialMultiTapWindow {
                    radialTapLastRelease = nil
                    return emitRadialPhase(.open(center: location), type: type)
                }
            } else if !triggerHeld, radialTriggerWasHeld, !radialActive {
                if !radialComboChordActive {
                    radialTapLastRelease = (tapKey, now)
                }
                radialComboChordActive = false
            } else if radialActive, !triggerHeld {
                return emitRadialPhase(.commit, type: type)
            }
            radialTriggerWasHeld = triggerHeld
            return false
        case .mouseMoved:
            guard radialActive else { return false }
            return emitRadialPhase(.update(cursor: location), type: type)
        default:
            return false
        }
    }

    /// Maps key-down events to radial actions while the menu is open.
    func handleRadialKeyDown(_ event: CGEvent) -> Bool {
        guard radialActive else { return false }
        guard let radialPhaseHandler else { return true }
        if Self.isRadialDismissKey(event) {
            Task { @MainActor in radialPhaseHandler(.cancel) }
            return true
        }
        if let action = Self.radialAction(for: event) {
            Task { @MainActor in radialPhaseHandler(.selectAction(action)) }
        }
        return true
    }

    private static func isRadialDismissKey(_ event: CGEvent) -> Bool {
        guard let nsEvent = NSEvent(cgEvent: event) else { return false }
        if nsEvent.keyCode == 53 { return true } // Esc
        let lowered = nsEvent.charactersIgnoringModifiers?.lowercased() ?? ""
        return lowered.first.map { RadialMenuLayout.dismissKeys.contains($0) } ?? false
    }

    private static func radialAction(for event: CGEvent) -> WindowAction? {
        guard let nsEvent = NSEvent(cgEvent: event) else { return nil }
        let lowered = nsEvent.charactersIgnoringModifiers?.lowercased() ?? ""
        guard let first = lowered.first else { return nil }
        return RadialMenuLayout.action(forKey: first)
    }

    /// Marks chorded use (e.g. ⌘A) so the subsequent modifier release is not counted as tap 1.
    func noteRadialComboKeyDown(_ event: CGEvent) {
        guard radialTriggerTapCount > 1 else { return }
        guard !radialActive else { return }
        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        guard !ModifierKeyCodes.isModifier(keyCode) else { return }
        let modifiers = WindowGestureModifier(cgEventFlags: event.flags)
        guard modifiers.radialExactMatch(radialTriggerModifier) else { return }
        radialComboChordActive = true
        radialTapLastRelease = nil
    }

    private func emitRadialPhase(_ phase: RadialPhase, type: CGEventType) -> Bool {
        switch phase {
        case .open:
            radialActive = true
        case .update, .selectAction:
            break
        case .commit, .cancel:
            radialActive = false
            radialTapLastRelease = nil
            radialTriggerWasHeld = false
        }
        if let radialPhaseHandler {
            Task { @MainActor in radialPhaseHandler(phase) }
        }
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

    /// Single-modifier radial triggers can use double-tap; combos require hold.
    var radialSingleTapKey: ModifierTapShortcut.Key? {
        let primary = normalizedPrimary
        if primary == .control {
            if contains(.leftControl), !contains(.rightControl) { return .leftControl }
            if contains(.rightControl), !contains(.leftControl) { return .rightControl }
            return .control
        }
        if primary == .option {
            if contains(.leftOption), !contains(.rightOption) { return .leftOption }
            if contains(.rightOption), !contains(.leftOption) { return .rightOption }
            return .option
        }
        if primary == .command {
            if contains(.leftCommand), !contains(.rightCommand) { return .leftCommand }
            if contains(.rightCommand), !contains(.leftCommand) { return .rightCommand }
            return .command
        }
        if primary == .shift {
            if contains(.leftShift), !contains(.rightShift) { return .leftShift }
            if contains(.rightShift), !contains(.leftShift) { return .rightShift }
            return .shift
        }
        if contains(.fn), primary.isEmpty { return .fn }
        return nil
    }
}
