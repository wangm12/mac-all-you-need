import ApplicationServices
import Core
import SwiftUI

/// Full settings surface for the Window Layouts → Radial tab.
struct RadialMenuSettingsTabView: View {
    @Binding var settings: WindowControlSettings
    let onSettingsChange: (WindowControlSettings) -> Void
    let axTrusted: Bool
    let layoutsEnabled: Bool

    var body: some View {
        radialMenuSection
        if settings.radialMenuEnabled {
            previewSection
            triggerSection
            selectionSection
            targetHighlightSection
            layoutActionsSection
        }
    }

    private var radialMenuSection: some View {
        MAYNSection(
            title: "Radial Menu",
            subtitle: "Hold the trigger, aim with the cursor (if enabled), then release the modifier or click to apply."
        ) {
            MAYNSettingsRow(
                title: "Radial menu",
                subtitle: "Show a pie-style window layout picker on the held trigger."
            ) {
                Toggle("", isOn: radialEnabledBinding)
                    .labelsHidden()
            }
            if settings.radialMenuEnabled, let status = blockedStatus {
                MAYNDivider()
                MAYNSettingsRow(title: status.title, subtitle: status.subtitle) {
                    StatusPill(text: status.pill, kind: status.kind)
                }
            }
        }
    }

    private var triggerSection: some View {
        MAYNSection(
            title: "Trigger",
            subtitle: triggerSectionSubtitle
        ) {
            MAYNSettingsRow(title: "Trigger modifier") {
                WindowGestureModifierPicker(
                    selection: modifierBinding(\.radialTriggerModifier),
                    tapCount: WindowGestureModifierPicker.tapCountBinding(
                        settings: $settings,
                        tapCountKeyPath: \.radialTriggerTapCount,
                        onChange: onSettingsChange
                    ),
                    defaultModifier: WindowControlSettings.default.radialTriggerModifier,
                    defaultTapCount: WindowControlSettings.default.radialTriggerTapCount
                )
            }
            if !triggerConflicts.isEmpty {
                MAYNDivider()
                MAYNSettingsRow(
                    title: "Modifier conflict",
                    subtitle: triggerConflicts.map(\.featureName).joined(separator: ", ")
                ) {
                    StatusPill(text: "Warning", kind: .warning)
                }
            }
        }
    }

    private var selectionSection: some View {
        MAYNSection(title: "Selection") {
            MAYNSettingsRow(
                title: "Lock to screen center",
                subtitle: "Anchor the radial menu to the screen center instead of the cursor."
            ) {
                Toggle("", isOn: boolBinding(\.radialLockToCenter)).labelsHidden()
            }
            MAYNDivider()
            MAYNSettingsRow(
                title: "Cursor selection",
                subtitle: "Select a layout by cursor angle while the menu is open."
            ) {
                Toggle("", isOn: boolBinding(\.radialCursorSelectionEnabled)).labelsHidden()
            }
        }
    }

    private var targetHighlightSection: some View {
        MAYNSection(
            title: "Target Highlight",
            subtitle: "Outline the window that will move so it is obvious on busy desktops."
        ) {
            MAYNSettingsRow(title: "Highlight window", subtitle: "Show a glowing border on the focused window.") {
                Toggle("", isOn: boolBinding(\.radialTargetHighlightEnabled)).labelsHidden()
            }
            if settings.radialTargetHighlightEnabled {
                MAYNDivider()
                MAYNSettingsRow(title: "Border color") {
                    highlightColorPicker
                }
            }
        }
    }

    private var previewSection: some View {
        MAYNSection(title: "Preview") {
            RadialSettingsPreview()
                .frame(maxWidth: .infinity)
                .padding(.vertical, MAYNControlMetrics.rowVerticalPadding * 2)
        }
    }

    private var layoutActionsSection: some View {
        MAYNSection(
            title: "Layout Actions",
            subtitle: "Press these keys while the radial menu is open. Esc or X dismisses without applying a layout."
        ) {
            ForEach(RadialMenuLayout.ringActions.indices, id: \.self) { index in
                if index > 0 { MAYNDivider() }
                let action = RadialMenuLayout.ringActions[index]
                layoutActionRow(action: action)
            }
            MAYNDivider()
            layoutActionRow(action: RadialMenuLayout.centerAction)
            MAYNDivider()
            MAYNSettingsRow(title: "Layout keys", subtitle: "Restore default WASD-style bindings.") {
                MAYNButton("Reset defaults", role: .secondary) {
                    var next = settings
                    next.radialMenuKeyBindings = .default
                    settings = next
                    onSettingsChange(next)
                }
            }
        }
    }

    private func layoutActionRow(action: WindowAction) -> some View {
        MAYNSettingsRow(
            title: RadialMenuSettingsPresentation.actionTitle(action),
            leading: {
                Image(systemName: action.symbolName)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(MAYNTheme.muted)
                    .frame(width: 22, height: 22)
            }
        ) {
            radialKeyField(for: action)
        }
    }

    private func radialKeyField(for action: WindowAction) -> some View {
        MAYNTextField(
            placeholder: "—",
            text: radialKeyBinding(for: action),
            width: 44,
            alignment: .center,
            font: .system(.callout, design: .monospaced)
        )
    }

    private func radialKeyBinding(for action: WindowAction) -> Binding<String> {
        let raw = action.rawValue
        return Binding {
            settings.radialMenuKeyBindings.bindings[raw] ?? ""
        } set: { newValue in
            var next = settings
            var dict = next.radialMenuKeyBindings.bindings
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if let first = trimmed.first, first.isLetter, !RadialMenuKeyBindings.reservedKeys.contains(first) {
                dict[raw] = String(first)
            } else if trimmed.isEmpty {
                dict[raw] = RadialMenuKeyBindings.defaultBindings[raw] ?? ""
            } else {
                return
            }
            next.radialMenuKeyBindings = RadialMenuKeyBindings(bindings: dict).replacingDuplicateKeys()
            settings = next
            onSettingsChange(next)
        }
    }

    @ViewBuilder
    private var highlightColorPicker: some View {
        VStack(alignment: .trailing, spacing: 8) {
            HStack(spacing: 8) {
                ForEach(RadialHighlightColorPreset.allCases) { preset in
                    Button {
                        applyColor(preset.color)
                    } label: {
                        Circle()
                            .fill(preset.color.swiftUIColor)
                            .frame(width: 20, height: 20)
                            .overlay(
                                Circle().strokeBorder(MAYNTheme.subtleBorder, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            ColorPicker(
                "",
                selection: Binding(
                    get: { settings.radialTargetHighlightColor.swiftUIColor },
                    set: { applySwiftUIColor($0) }
                ),
                supportsOpacity: false
            )
            .labelsHidden()
        }
    }

    private var radialEnabledBinding: Binding<Bool> {
        Binding {
            settings.radialMenuEnabled
        } set: { enabled in
            var next = settings
            next.radialMenuEnabled = enabled
            if enabled, !settings.radialCursorSelectionEnabled {
                next.radialCursorSelectionEnabled = true
            }
            settings = next
            onSettingsChange(next)
        }
    }

    private var triggerSectionSubtitle: String {
        if settings.radialTriggerTapCount > 1 {
            return "Double-tap this modifier to open the radial menu."
        }
        return "Hold this modifier combination to open the radial menu."
    }

    private var triggerConflicts: [RadialTriggerConflict.Conflict] {
        RadialTriggerConflict.conflicts(in: settings)
    }

    private var blockedStatus: RadialBlockedStatus? {
        if !layoutsEnabled {
            return RadialBlockedStatus(
                title: "Window Layouts off",
                subtitle: "Enable Window Layouts for the radial menu to run.",
                pill: "Off",
                kind: .neutral
            )
        }
        if !axTrusted {
            return RadialBlockedStatus(
                title: "Accessibility required",
                subtitle: "Grant Accessibility so Mac All You Need can read and move windows.",
                pill: "Needs permission",
                kind: .warning
            )
        }
        return nil
    }

    private func boolBinding(_ keyPath: WritableKeyPath<WindowControlSettings, Bool>) -> Binding<Bool> {
        Binding {
            settings[keyPath: keyPath]
        } set: { value in
            var next = settings
            next[keyPath: keyPath] = value
            settings = next
            onSettingsChange(next)
        }
    }

    private func modifierBinding(_ keyPath: WritableKeyPath<WindowControlSettings, WindowGestureModifier>) -> Binding<WindowGestureModifier> {
        Binding {
            settings[keyPath: keyPath]
        } set: { value in
            var next = settings
            next[keyPath: keyPath] = value
            settings = next
            onSettingsChange(next)
        }
    }

    private func applyColor(_ color: RadialHighlightColor) {
        var next = settings
        next.radialTargetHighlightColor = color
        settings = next
        onSettingsChange(next)
    }

    private func applySwiftUIColor(_ color: Color) {
        #if canImport(AppKit)
        let ns = NSColor(color)
        applyColor(RadialHighlightColor(
            red: ns.redComponent,
            green: ns.greenComponent,
            blue: ns.blueComponent,
            alpha: 1
        ))
        #endif
    }
}

private enum RadialHighlightColorPreset: String, CaseIterable, Identifiable {
    case focus
    case blue
    case green
    case orange

    var id: String { rawValue }

    var color: RadialHighlightColor {
        switch self {
        case .focus: .focusRingDefault
        case .blue: .presetBlue
        case .green: .presetGreen
        case .orange: .presetOrange
        }
    }
}

private struct RadialBlockedStatus {
    let title: String
    let subtitle: String
    let pill: String
    let kind: StatusPill.Kind
}

enum RadialMenuSettingsPresentation {
    static func actionTitle(_ action: WindowAction) -> String {
        switch action {
        case .topHalf: "Top Half"
        case .topRight: "Top Right"
        case .rightHalf: "Right Half"
        case .bottomRight: "Bottom Right"
        case .bottomHalf: "Bottom Half"
        case .bottomLeft: "Bottom Left"
        case .leftHalf: "Left Half"
        case .topLeft: "Top Left"
        case .maximize: "Maximize"
        default: String(describing: action)
        }
    }

    static func sectionTitles(whenEnabled: Bool) -> [String] {
        var titles = ["Radial Menu"]
        guard whenEnabled else { return titles }
        titles += ["Preview", "Trigger", "Selection", "Target Highlight", "Layout Actions"]
        return titles
    }
}
