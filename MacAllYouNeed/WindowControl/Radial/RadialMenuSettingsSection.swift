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
            subtitle: "Hold Control-Option to open a radial layout picker; release over a direction to apply it."
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
}
