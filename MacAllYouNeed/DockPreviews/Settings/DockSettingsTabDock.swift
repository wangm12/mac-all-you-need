import ApplicationServices
import SwiftUI

struct DockSettingsTabDock: View {
    var onSettingsChanged: (() -> Void)?
    @State private var hub = DockHubSettingsStore.load()

    var body: some View {
        Group {
            featuresSection
            permissionsSection
        }
        .onAppear { hub = DockHubSettingsStore.load() }
    }

    private var featuresSection: some View {
        MAYNSection(title: "Features") {
            toggleRow("Dock hover previews", "Show window thumbnails when hovering a Dock icon.", \.master.enableDockPreviews)
            MAYNDivider()
            toggleRow("Window switcher", "Alt+Tab–style window switcher with configurable keybinds.", \.master.enableWindowSwitcher)
            MAYNDivider()
            toggleRow("Cmd+Tab enhancements", "Intercept the system Cmd+Tab switcher and show window previews.", \.master.enableCmdTabEnhancements)
            MAYNDivider()
            toggleRow("Dock locking", "Keep the Dock on a specific display in multi-monitor setups.", \.master.enableDockLocking)
            MAYNDivider()
            toggleRow("Active app indicator", "Show a colored bar beneath the active application's Dock icon.", \.master.enableActiveAppIndicator)
        }
    }

    private var permissionsSection: some View {
        MAYNSection(title: "Permissions") {
            MAYNSettingsRow(
                title: "Screen Recording",
                subtitle: "Required for window thumbnails and live preview."
            ) {
                StatusPill(
                    text: DockPreviewPermissionGate.screenRecordingGranted() ? "Granted" : "Required",
                    kind: DockPreviewPermissionGate.screenRecordingGranted() ? .success : .warning
                )
            }
            MAYNDivider()
            MAYNSettingsRow(
                title: "Accessibility",
                subtitle: "Required for window switcher and Cmd+Tab interception."
            ) {
                let granted = AXIsProcessTrusted()
                StatusPill(
                    text: granted ? "Granted" : "Required",
                    kind: granted ? .success : .warning
                )
            }
        }
    }

    private func toggleRow(_ title: String, _ subtitle: String, _ keyPath: WritableKeyPath<DockHubSettings, Bool>) -> some View {
        MAYNSettingsRow(title: title, subtitle: subtitle) {
            Toggle("", isOn: Binding(
                get: { hub[keyPath: keyPath] },
                set: { hub[keyPath: keyPath] = $0; persist() }
            )).labelsHidden()
        }
    }

    private func persist() {
        DockHubSettingsStore.save(hub)
        onSettingsChanged?()
    }
}
