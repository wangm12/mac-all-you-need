import Core
import SwiftUI

/// Radial-menu settings section. Extracted from `WindowControlSettingsView` so
/// that file stays within design-system length limits. Binds directly to the
/// shared `WindowControlSettings`; the parent persists changes via its store.
struct RadialMenuSettingsSection: View {
    @Binding var settings: WindowControlSettings
    let onChange: (WindowControlSettings) -> Void

    var body: some View {
        MAYNSection(
            title: "Radial Menu",
            subtitle: radialSectionSubtitle
        ) {
            MAYNSettingsRow(
                title: "Radial menu",
                subtitle: "Show a pie-style window layout picker on the held trigger."
            ) {
                Toggle("", isOn: boolBinding(\.radialMenuEnabled))
                    .labelsHidden()
            }
            if settings.radialMenuEnabled {
                MAYNDivider()
                MAYNSettingsRow(
                    title: "Trigger modifier",
                    subtitle: radialTriggerSubtitle
                ) {
                    WindowGestureModifierPicker(
                        selection: modifierBinding(\.radialTriggerModifier),
                        tapCount: tapCountBinding(\.radialTriggerTapCount),
                        defaultModifier: WindowControlSettings.default.radialTriggerModifier,
                        defaultTapCount: WindowControlSettings.default.radialTriggerTapCount
                    )
                }
                MAYNDivider()
                MAYNSettingsRow(
                    title: "Lock to screen center",
                    subtitle: "Anchor the radial menu to the screen center instead of the cursor."
                ) {
                    Toggle("", isOn: boolBinding(\.radialLockToCenter))
                        .labelsHidden()
                }
                MAYNDivider()
                MAYNSettingsRow(
                    title: "Cursor selection",
                    subtitle: "Select a layout by cursor angle while the menu is open."
                ) {
                    Toggle("", isOn: boolBinding(\.radialCursorSelectionEnabled))
                        .labelsHidden()
                }
                MAYNDivider()
                HStack {
                    Spacer()
                    RadialSettingsPreview()
                    Spacer()
                }
            }
        }
    }

    private func boolBinding(_ keyPath: WritableKeyPath<WindowControlSettings, Bool>) -> Binding<Bool> {
        Binding {
            settings[keyPath: keyPath]
        } set: { value in
            var next = settings
            next[keyPath: keyPath] = value
            settings = next
            onChange(next)
        }
    }

    private var radialSectionSubtitle: String {
        if settings.radialTriggerTapCount > 1 {
            return "Double-tap the configured modifier to open a radial layout picker; click a direction to apply it."
        }
        return "Hold the configured modifier combination to open a radial layout picker; click a direction to apply it."
    }

    private var radialTriggerSubtitle: String {
        if settings.radialTriggerTapCount > 1 {
            return "Double-tap this modifier to open the radial menu."
        }
        return "Hold this modifier combination to open the radial menu."
    }

    private func tapCountBinding(_ keyPath: WritableKeyPath<WindowControlSettings, Int>) -> Binding<Int> {
        Binding {
            settings[keyPath: keyPath]
        } set: { value in
            var next = settings
            next[keyPath: keyPath] = min(max(value, 1), 2)
            settings = next
            onChange(next)
        }
    }

    private func modifierBinding(_ keyPath: WritableKeyPath<WindowControlSettings, WindowGestureModifier>) -> Binding<WindowGestureModifier> {
        Binding {
            settings[keyPath: keyPath]
        } set: { value in
            var next = settings
            next[keyPath: keyPath] = value
            settings = next
            onChange(next)
        }
    }
}
