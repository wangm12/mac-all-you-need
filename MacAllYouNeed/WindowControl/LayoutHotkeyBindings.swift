import Core
import CoreGraphics
import Platform

/// Keyboard shortcut bindings for window-layout actions, matched from CGEvent traffic.
struct LayoutHotkeyBinding: Equatable, Sendable {
    let keyCode: UInt32
    let modifiers: HotkeyDescriptor.Modifiers
    let action: WindowAction
}

enum LayoutHotkeyBindings {
    static func from(_ map: [HotkeyAction: [HotkeyDescriptor]]) -> [LayoutHotkeyBinding] {
        map.flatMap { action, descriptors -> [LayoutHotkeyBinding] in
            guard let windowAction = action.windowAction else { return [] }
            return descriptors.compactMap { descriptor in
                guard !descriptor.isModifierTap else { return nil }
                return LayoutHotkeyBinding(
                    keyCode: descriptor.keyCode,
                    modifiers: descriptor.modifiers,
                    action: windowAction
                )
            }
        }
    }

    static func action(for event: CGEvent, bindings: [LayoutHotkeyBinding]) -> WindowAction? {
        guard !bindings.isEmpty else { return nil }
        let keyCode = UInt32(event.getIntegerValueField(.keyboardEventKeycode))
        let modifiers = carbonModifiers(from: event.flags)
        return bindings.first { $0.keyCode == keyCode && $0.modifiers == modifiers }?.action
    }

    /// Maps CGEvent modifier flags to Carbon-style masks used by `HotkeyDescriptor`.
    /// Ignores `maskSecondaryFn` — MacBook arrow keys often report a spurious Fn bit
    /// that would prevent matching registered ⌃⌥ arrow shortcuts.
    static func carbonModifiers(from flags: CGEventFlags) -> HotkeyDescriptor.Modifiers {
        var modifiers: HotkeyDescriptor.Modifiers = []
        if flags.contains(.maskCommand) { modifiers.insert(.command) }
        if flags.contains(.maskAlternate) { modifiers.insert(.option) }
        if flags.contains(.maskControl) { modifiers.insert(.control) }
        if flags.contains(.maskShift) { modifiers.insert(.shift) }
        return modifiers
    }
}
