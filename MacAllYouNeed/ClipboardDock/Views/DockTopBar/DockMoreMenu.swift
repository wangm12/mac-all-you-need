import Core
import SwiftUI

struct DockMoreMenu: View {
    /// Called before opening Settings so the dock can hide itself — the dock
    /// window sits at `.popUpMenu` level which would otherwise cover the
    /// Settings window and make it look like nothing happened.
    let dismissDock: () -> Void
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Menu {
            // Flat structure — submenus inside a SwiftUI Menu hosted in a
            // borderless nonactivating NSPanel are unreliable; clicks on
            // nested items frequently never reach the action closure.
            Button("Open Privacy Settings…") {
                AppGroupSettings.defaults.set("privacy", forKey: "settings.selectedTab")
                openSettingsAndDismiss()
            }
            Button("Pause Capture for 60s") {
                NotificationCenter.default.post(name: .pauseCaptureRequested, object: nil)
            }

            Divider()

            Button("Clear Older Than 1 Day") {
                NotificationCenter.default.post(name: .clearClipboardOlderThanRequested, object: 1)
            }
            Button("Clear Older Than 7 Days") {
                NotificationCenter.default.post(name: .clearClipboardOlderThanRequested, object: 7)
            }
            Button("Clear Older Than 30 Days") {
                NotificationCenter.default.post(name: .clearClipboardOlderThanRequested, object: 30)
            }

            Divider()

            Button("Open Settings…") {
                AppGroupSettings.defaults.set("general", forKey: "settings.selectedTab")
                openSettingsAndDismiss()
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        // Drop the trailing ▾ chevron — the ellipsis itself is a clear
        // affordance, the chevron is visual noise.
        .menuIndicator(.hidden)
        .frame(width: 28, height: 28)
    }

    private func openSettingsAndDismiss() {
        dismissDock()
        // Activate the LSUIElement app and bring up the SwiftUI Settings
        // scene. The dock has been dismissed so the Settings window won't be
        // covered by our `.popUpMenu`-level panel.
        NSApp.activate(ignoringOtherApps: true)
        openSettings()
    }
}
