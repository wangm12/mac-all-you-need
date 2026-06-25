import ApplicationServices
import Core
import Platform
import SwiftUI

/// Menu-bar quick snap grid (Rectangle-style regions) for the frontmost window.
struct WindowLayoutsPopoverView: View {
    let controller: AppController

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var layoutSettings = WindowControlSettingsStore.load()
    @State private var hotkeyMap: [HotkeyAction: [HotkeyDescriptor]] = HotkeyMapStore.load()

    /// Display order: corners, halves, maximize, then auxiliary + display moves.
    private static let actionsInOrder: [WindowAction] = [
        .topLeft, .topRight,
        .topHalf, .bottomHalf,
        .leftHalf, .rightHalf,
        .bottomLeft, .bottomRight,
        .maximize, .almostMaximize,
        .center, .restore,
        .previousDisplay, .nextDisplay
    ]

    private static let windowActionToHotkeyAction: [WindowAction: HotkeyAction] = [
        .leftHalf: .windowLeftHalf,
        .rightHalf: .windowRightHalf,
        .topHalf: .windowTopHalf,
        .bottomHalf: .windowBottomHalf,
        .topLeft: .windowTopLeft,
        .topRight: .windowTopRight,
        .bottomLeft: .windowBottomLeft,
        .bottomRight: .windowBottomRight,
        .maximize: .windowMaximize,
        .almostMaximize: .windowAlmostMaximize,
        .center: .windowCenter,
        .restore: .windowRestore,
        .nextDisplay: .windowNextDisplay,
        .previousDisplay: .windowPreviousDisplay
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            popoverHeader
            if !controller.windowControl.windowLayoutsEnabled {
                unavailableBlock(
                    title: "Window Layouts is off",
                    detail: "Enable the Window Layouts feature from the Dashboard to snap windows from here."
                )
            } else if !layoutSettings.enabled {
                unavailableBlock(
                    title: "Window Layouts is disabled",
                    detail: "Turn on Window Layouts in settings to use keyboard shortcuts, this grid, and edge snap."
                )
            } else if !AXIsProcessTrusted() {
                unavailableBlock(
                    title: "Accessibility required",
                    detail: "macOS needs Accessibility permission for Mac All You Need to move other apps’ windows."
                )
            } else {
                Text("Snap front window")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 8),
                        GridItem(.flexible(), spacing: 8)
                    ],
                    spacing: 8
                ) {
                    ForEach(Self.actionsInOrder, id: \.self) { action in
                        snapCell(action)
                    }
                }

                Button("Radial settings…") {
                    openRadialSettingsInMainApp()
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(MAYNTheme.window)
        .onAppear {
            layoutSettings = WindowControlSettingsStore.load()
            hotkeyMap = HotkeyMapStore.load()
        }
    }

    private var popoverHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Window Layouts")
                    .font(.headline.weight(.semibold))
                Text("Snap the front window, or open the full Window Layouts page for shortcuts, ignored apps, and diagnostics.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            MAYNButton("Open Window Layouts", role: .primary, height: HotkeyChipPresentation.compactHeight) {
                openWindowLayoutsInMainApp()
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(MAYNTheme.panel)
    }

    @ViewBuilder
    private func unavailableBlock(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            MAYNButton("Open Window Layouts", role: .primary, height: MAYNControlMetrics.controlHeight) {
                openWindowLayoutsInMainApp()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func shortcutDisplay(for action: WindowAction) -> String? {
        guard let hotkeyAction = Self.windowActionToHotkeyAction[action],
              let descriptor = hotkeyMap[hotkeyAction]?.first
        else { return nil }
        return descriptor.display
    }

    private func snapCell(_ action: WindowAction) -> some View {
        let enabled = controller.windowControl.windowActionPerformerAvailable
        let shortcut = shortcutDisplay(for: action)
        return Button {
            controller.windowControl.perform(action: action)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: action.symbolName)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(enabled ? Color.primary : Color.secondary.opacity(0.45))
                    .frame(width: 18)
                Text(action.title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 4)
                if let shortcut {
                    ShortcutChip(text: shortcut, height: HotkeyChipPresentation.compactHeight)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(MAYNTheme.elevated, in: RoundedRectangle(cornerRadius: MAYNControlMetrics.controlRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: MAYNControlMetrics.controlRadius, style: .continuous)
                    .stroke(MAYNTheme.subtleBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(action.title)
        .opacity(enabled ? 1 : 0.55)
        .animation(MAYNMotion.fastAnimation(reduceMotion: reduceMotion), value: enabled)
    }

    private func openWindowLayoutsInMainApp() {
        AppGroupSettings.defaults.set(WindowLayoutsFunctionTab.shortcuts.rawValue, forKey: WindowLayoutsFunctionTab.storageKey)
        controller.showMainWindow(destination: .windowLayouts)
    }

    private func openRadialSettingsInMainApp() {
        AppGroupSettings.defaults.set(WindowLayoutsFunctionTab.radial.rawValue, forKey: WindowLayoutsFunctionTab.storageKey)
        controller.showMainWindow(destination: .windowLayouts)
    }
}
