import AppKit
import Core
import CoreGraphics
import Foundation

/// Global singleton that detects modifier-tap patterns (press + quick release
/// of a single modifier with no other key pressed) and dispatches registered
/// callbacks. Bypasses Carbon's `RegisterEventHotKey` which rejects modifier-
/// only combos.
///
/// - Never suppresses events — modifiers keep working normally for combos.
/// - The underlying CGEventTap is installed only while ≥1 shortcut is registered
///   and uninstalled when all are removed.
/// - Thread-safe: registration/unregistration are serialized; callbacks always
///   arrive on the main queue.
public final class ModifierTapDispatcher {
    public static let shared = ModifierTapDispatcher()

    // MARK: - Token

    public struct Token: Hashable, Sendable {
        let id: UInt64
    }

    // MARK: - Timing configuration

    /// Maximum duration (seconds) of a modifier press-to-release to count as
    /// a tap. Longer presses are treated as "held" and ignored.
    public var tapHoldMax: TimeInterval = 0.25

    /// Window (seconds) within which a second tap must arrive to be counted
    /// as part of a multi-tap sequence.
    public var multiTapWindow: TimeInterval = 0.28

    // MARK: - Private state

    private let lock = NSLock()
    private var registrations: [Token: (ModifierTapShortcut, () -> Void)] = [:]
    private var nextTokenID: UInt64 = 1

    // CGEventTap lifecycle
    private var tapController: CGEventTapController?

    // Per-key timing state (main queue only)
    private var pressStart: [ModifierTapShortcut.Key: TimeInterval] = [:]
    private var nonModifierDownSincePress: Set<ModifierTapShortcut.Key> = []
    private var pendingTap: (key: ModifierTapShortcut.Key, count: Int, time: TimeInterval)?
    private var pendingTimer: DispatchWorkItem?
    private var lastFlags: CGEventFlags = []

    // MARK: - Init

    private init() {}

    // MARK: - Registration

    public func register(_ shortcut: ModifierTapShortcut, callback: @escaping () -> Void) -> Token {
        lock.lock()
        let token = Token(id: nextTokenID)
        nextTokenID += 1
        registrations[token] = (shortcut, callback)
        let needsInstall = registrations.count == 1
        lock.unlock()

        if needsInstall {
            DispatchQueue.main.async { self.installTap() }
        }
        return token
    }

    public func unregister(_ token: Token) {
        lock.lock()
        registrations.removeValue(forKey: token)
        let needsRemove = registrations.isEmpty
        lock.unlock()

        if needsRemove {
            DispatchQueue.main.async { self.removeTap() }
        }
    }

    // MARK: - CGEventTap lifecycle

    private func installTap() {
        guard tapController == nil else { return }

        let mask = CGEventMask(
            (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.tapDisabledByTimeout.rawValue)
            | (1 << CGEventType.tapDisabledByUserInput.rawValue)
        )
        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        let controller = CGEventTapController(
            tap: .cghidEventTap,
            place: .tailAppendEventTap,  // tail: never suppresses, minimal interference
            options: .listenOnly,         // listen-only: cannot suppress events
            eventsOfInterest: mask,
            runLoop: .main,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let d = Unmanaged<ModifierTapDispatcher>.fromOpaque(userInfo).takeUnretainedValue()
                d.handleEvent(type: type, event: event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: userInfo
        )
        do {
            try controller.install()
            controller.enable()
            tapController = controller
        } catch {
            return
        }
        lastFlags = []
    }

    private func removeTap() {
        tapController?.uninstall()
        tapController = nil
        pressStart.removeAll()
        nonModifierDownSincePress.removeAll()
        cancelPendingTimer()
        pendingTap = nil
        lastFlags = []
    }

    // MARK: - Event handling (main queue via CFRunLoopGetMain)

    private func handleEvent(type: CGEventType, event: CGEvent) {
        // Must be called on the main thread (CGEventTap is on main run loop).
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            tapController?.reenableAfterTimeout()

        case .keyDown:
            // Any non-modifier key pressed while a modifier is held cancels tap.
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            if !isModifierKeyCode(Int(keyCode)) {
                for key in pressStart.keys {
                    nonModifierDownSincePress.insert(key)
                }
            }

        case .flagsChanged:
            handleFlagsChanged(newFlags: event.flags)

        default:
            break
        }
    }

    private func handleFlagsChanged(newFlags: CGEventFlags) {
        let now = ProcessInfo.processInfo.systemUptime
        let transitions = modifierTransitions(from: lastFlags, to: newFlags)
        lastFlags = newFlags

        for (key, pressed) in transitions {
            if pressed {
                // Modifier pressed: record start time, clear other-key flag.
                pressStart[key] = now
                nonModifierDownSincePress.remove(key)
            } else {
                // Modifier released.
                guard let start = pressStart.removeValue(forKey: key) else { continue }

                // Reject if another key was pressed while this modifier was held.
                if nonModifierDownSincePress.remove(key) != nil { continue }

                // Reject if held too long (user was using it as a hold, not a tap).
                guard now - start <= tapHoldMax else { continue }

                // Valid tap. Determine count.
                let tapCount: Int
                if let pending = pendingTap,
                   pending.key == key,
                   now - pending.time <= multiTapWindow {
                    tapCount = pending.count + 1
                    cancelPendingTimer()
                } else {
                    tapCount = 1
                    cancelPendingTimer()
                }
                pendingTap = (key: key, count: tapCount, time: now)

                // Dispatch immediately if no double-tap sibling exists for this key,
                // otherwise wait the multi-tap window in case a second tap is coming.
                if !hasHigherCountRegistration(for: key, count: tapCount) {
                    firePendingTap()
                } else {
                    schedulePendingTimer()
                }
            }
        }
    }

    // MARK: - Dispatch helpers

    private func schedulePendingTimer() {
        let item = DispatchWorkItem { [weak self] in
            self?.firePendingTap()
        }
        pendingTimer = item
        DispatchQueue.main.asyncAfter(deadline: .now() + multiTapWindow, execute: item)
    }

    private func cancelPendingTimer() {
        pendingTimer?.cancel()
        pendingTimer = nil
    }

    private func firePendingTap() {
        cancelPendingTimer()
        guard let tap = pendingTap else { return }
        pendingTap = nil

        let shortcut = ModifierTapShortcut(key: tap.key, count: tap.count)
        let callbacks = matchingCallbacks(for: shortcut)
        for cb in callbacks {
            DispatchQueue.main.async(execute: cb)
        }
    }

    private func matchingCallbacks(for shortcut: ModifierTapShortcut) -> [() -> Void] {
        lock.lock()
        defer { lock.unlock() }
        return registrations.values.compactMap { (s, cb) in
            s == shortcut ? cb : nil
        }
    }

    private func hasHigherCountRegistration(for key: ModifierTapShortcut.Key, count: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return registrations.values.contains { (s, _) in
            s.key == key && s.count > count
        }
    }

    // MARK: - Modifier key mapping

    /// Returns `[(key, isPressed)]` for each modifier that changed between flags.
    private func modifierTransitions(
        from old: CGEventFlags,
        to new: CGEventFlags
    ) -> [(ModifierTapShortcut.Key, Bool)] {
        var result: [(ModifierTapShortcut.Key, Bool)] = []
        let rawOld = old.rawValue
        let rawNew = new.rawValue

        func check(key: ModifierTapShortcut.Key, genericMask: CGEventFlags, deviceMask: UInt64) {
            let oldHeld = rawOld & deviceMask != 0 || old.contains(genericMask) && rawOld & selfDeviceMask(genericMask) == 0
            let newHeld = rawNew & deviceMask != 0 || new.contains(genericMask) && rawNew & selfDeviceMask(genericMask) == 0
            if oldHeld != newHeld {
                result.append((key, newHeld))
            }
        }

        // Physical device bits (from CGModifierDeviceBit)
        func physicalTransition(key: ModifierTapShortcut.Key, mask: UInt64) {
            let wasOn = rawOld & mask != 0
            let isOn  = rawNew & mask != 0
            if wasOn != isOn { result.append((key, isOn)) }
        }

        physicalTransition(key: .leftControl,  mask: CGModifierDeviceBit.leftControl)
        physicalTransition(key: .rightControl, mask: CGModifierDeviceBit.rightControl)
        physicalTransition(key: .leftOption,   mask: CGModifierDeviceBit.leftOption)
        physicalTransition(key: .rightOption,  mask: CGModifierDeviceBit.rightOption)
        physicalTransition(key: .leftCommand,  mask: CGModifierDeviceBit.leftCommand)
        physicalTransition(key: .rightCommand, mask: CGModifierDeviceBit.rightCommand)
        physicalTransition(key: .leftShift,    mask: CGModifierDeviceBit.leftShift)
        physicalTransition(key: .rightShift,   mask: CGModifierDeviceBit.rightShift)

        // Generic modifiers — only fire if no physical bit handled a transition.
        let handledKeys = Set(result.map(\.0))

        func genericTransition(key: ModifierTapShortcut.Key, flag: CGEventFlags, physicals: Set<ModifierTapShortcut.Key>) {
            guard physicals.isDisjoint(with: handledKeys) else { return }
            let wasOn = old.contains(flag)
            let isOn  = new.contains(flag)
            if wasOn != isOn { result.append((key, isOn)) }
        }

        genericTransition(key: .control, flag: .maskControl,     physicals: [.leftControl, .rightControl])
        genericTransition(key: .option,  flag: .maskAlternate,   physicals: [.leftOption, .rightOption])
        genericTransition(key: .command, flag: .maskCommand,      physicals: [.leftCommand, .rightCommand])
        genericTransition(key: .shift,   flag: .maskShift,        physicals: [.leftShift, .rightShift])
        genericTransition(key: .fn,      flag: .maskSecondaryFn,  physicals: [])

        return result
    }

    private func selfDeviceMask(_ flag: CGEventFlags) -> UInt64 {
        switch flag {
        case .maskControl:    return CGModifierDeviceBit.leftControl | CGModifierDeviceBit.rightControl
        case .maskAlternate:  return CGModifierDeviceBit.leftOption | CGModifierDeviceBit.rightOption
        case .maskCommand:    return CGModifierDeviceBit.leftCommand | CGModifierDeviceBit.rightCommand
        case .maskShift:      return CGModifierDeviceBit.leftShift | CGModifierDeviceBit.rightShift
        default:              return 0
        }
    }

    private func isModifierKeyCode(_ code: Int) -> Bool {
        switch code {
        case 54, 55, 56, 57, 58, 59, 60, 61, 62, 63: // Cmd L/R, Shift L/R, Caps, Option L/R, Control L/R, Fn
            true
        default:
            false
        }
    }
}
