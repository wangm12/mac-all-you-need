import Core
import Platform
import SwiftUI

/// Window Grab / radial trigger modifier picker. Reuses `HotkeyRecorderControl` so all
/// keyboard input handling (CGEventTap, flagsChanged override, floating keyboard popup)
/// is shared with the shortcut recorder.
///
/// Pass `tapCount` when the gesture supports double-tap modifiers (radial menu). Hold-only
/// gestures (Window Grab drag, edge snap) omit `tapCount` and reject double-tap recording.
struct WindowGestureModifierPicker: View {
    @Binding var selection: WindowGestureModifier
    /// When set, records and persists `ModifierTapShortcut.count` (1 or 2).
    var tapCount: Binding<Int>?
    var defaultModifier: WindowGestureModifier = .option
    var defaultTapCount: Int = 1
    var width: CGFloat = 112

    private var allowsDoubleTap: Bool { tapCount != nil }

    var body: some View {
        HotkeyRecorderControl(
            descriptor: descriptorBinding,
            issueMessage: nil,
            candidateIssueMessage: candidateIssueMessage,
            defaultDescriptor: descriptor(from: defaultModifier, tapCount: defaultTapCount),
            recorderWidth: width,
            chipDisplayOverride: chipDisplay,
            reset: {
                selection = defaultModifier
                tapCount?.wrappedValue = defaultTapCount
            }
        )
    }

    // MARK: - Binding bridge

    private var descriptorBinding: Binding<HotkeyDescriptor> {
        Binding {
            descriptor(from: selection, tapCount: effectiveTapCount)
        } set: { newDescriptor in
            guard let tap = newDescriptor.modifierTap else { return }
            selection = windowGestureModifier(from: tap.key)
            if let tapCount {
                tapCount.wrappedValue = min(max(tap.count, 1), 2)
            }
        }
    }

    private var effectiveTapCount: Int {
        let stored = tapCount?.wrappedValue ?? 1
        return min(max(stored, 1), 2)
    }

    private func candidateIssueMessage(_ descriptor: HotkeyDescriptor) -> String? {
        guard let tap = descriptor.modifierTap else {
            return "Tap a modifier key — combos aren't supported here."
        }
        if !allowsDoubleTap, tap.count > 1 {
            return "Double-tap isn't supported for this gesture. Use a single modifier tap."
        }
        return nil
    }

    private func chipDisplay(_ descriptor: HotkeyDescriptor) -> String {
        HotkeyChipPresentation.displayText(descriptor.display)
    }

    private func descriptor(from modifier: WindowGestureModifier, tapCount: Int) -> HotkeyDescriptor {
        HotkeyDescriptor(modifierTap: ModifierTapShortcut(key: tapKey(from: modifier), count: tapCount))
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

// MARK: - Settings bindings

extension WindowGestureModifierPicker {
    /// Bridges `WindowControlSettings` modifier + tap-count fields to a recorder binding.
    static func tapCountBinding(
        settings: Binding<WindowControlSettings>,
        tapCountKeyPath: WritableKeyPath<WindowControlSettings, Int>,
        onChange: @escaping (WindowControlSettings) -> Void
    ) -> Binding<Int> {
        Binding {
            settings.wrappedValue[keyPath: tapCountKeyPath]
        } set: { value in
            var next = settings.wrappedValue
            next[keyPath: tapCountKeyPath] = min(max(value, 1), 2)
            settings.wrappedValue = next
            onChange(next)
        }
    }
}
