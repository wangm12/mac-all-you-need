import Core
import Platform
import SwiftUI

/// Window Grab modifier picker. Reuses `HotkeyRecorderControl` so all
/// keyboard input handling (CGEventTap, flagsChanged override, floating
/// keyboard popup) is shared with the shortcut recorder — no duplicate
/// NSView/NSViewRepresentable.
///
/// The chip is overridden to show the compact modifier glyph ("⌥")
/// instead of the verbose "Tap ⌥" form. The floating-keyboard summary
/// still uses the full display so the popup remains self-explanatory.
struct WindowGestureModifierPicker: View {
    @Binding var selection: WindowGestureModifier
    var defaultModifier: WindowGestureModifier = .option
    var width: CGFloat = 112

    var body: some View {
        HotkeyRecorderControl(
            descriptor: descriptorBinding,
            issueMessage: nil,
            candidateIssueMessage: candidateIssueMessage,
            defaultDescriptor: descriptor(from: defaultModifier),
            recorderWidth: width,
            chipDisplayOverride: chipDisplay,
            reset: { selection = defaultModifier }
        )
    }

    // MARK: - Binding bridge

    private var descriptorBinding: Binding<HotkeyDescriptor> {
        Binding {
            descriptor(from: selection)
        } set: { newDescriptor in
            // Only accept modifier-tap descriptors. Combos are rejected
            // upstream via `candidateIssueMessage` so this set won't see them.
            if let tap = newDescriptor.modifierTap {
                selection = windowGestureModifier(from: tap.key)
            }
        }
    }

    private func candidateIssueMessage(_ descriptor: HotkeyDescriptor) -> String? {
        descriptor.modifierTap == nil
            ? "Tap a modifier key — combos aren't supported here."
            : nil
    }

    private func chipDisplay(_ descriptor: HotkeyDescriptor) -> String {
        if let tap = descriptor.modifierTap {
            return tap.key.glyph
        }
        return descriptor.display
    }

    private func descriptor(from modifier: WindowGestureModifier) -> HotkeyDescriptor {
        HotkeyDescriptor(modifierTap: ModifierTapShortcut(key: tapKey(from: modifier), count: 1))
    }

    private func tapKey(from modifier: WindowGestureModifier) -> ModifierTapShortcut.Key {
        if modifier.contains(.leftCommand)  { return .leftCommand }
        if modifier.contains(.rightCommand) { return .rightCommand }
        if modifier.contains(.command)      { return .command }
        if modifier.contains(.leftOption)   { return .leftOption }
        if modifier.contains(.rightOption)  { return .rightOption }
        if modifier.contains(.option)       { return .option }
        if modifier.contains(.leftControl)  { return .leftControl }
        if modifier.contains(.rightControl) { return .rightControl }
        if modifier.contains(.control)      { return .control }
        if modifier.contains(.leftShift)    { return .leftShift }
        if modifier.contains(.rightShift)   { return .rightShift }
        if modifier.contains(.shift)        { return .shift }
        if modifier.contains(.fn)           { return .fn }
        return .option
    }

    private func windowGestureModifier(from key: ModifierTapShortcut.Key) -> WindowGestureModifier {
        switch key {
        case .command:      return .command
        case .option:       return .option
        case .control:      return .control
        case .shift:        return .shift
        case .fn:           return .fn
        case .leftCommand:  return .leftCommand
        case .rightCommand: return .rightCommand
        case .leftOption:   return .leftOption
        case .rightOption:  return .rightOption
        case .leftControl:  return .leftControl
        case .rightControl: return .rightControl
        case .leftShift:    return .leftShift
        case .rightShift:   return .rightShift
        }
    }
}
