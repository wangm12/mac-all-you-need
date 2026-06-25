import FeatureCore
import SwiftUI

enum WindowHubDescriptor {
    static func descriptor() -> FeatureDescriptor {
        FeatureDescriptor(
            id: .windowHub,
            displayName: "Windows",
            icon: "macwindow.on.rectangle",
            summary: "Search-first window and tab hub with cleanup and AI organize.",
            detailDescription: "Open a compact dashboard of running apps, windows, and tabs. Switch instantly, review cleanup batches, and run AI organize plans — no screenshots or background capture.",
            requiredPermissions: [.accessibility],
            hotkeys: [
                HotkeyDescriptor(identifier: "windowHub.open", displayName: "Open Window Hub"),
            ],
            activator: WindowHubFeatureActivator(),
            settingsTabFactory: { AnyView(WindowHubSettingsView()) }
        )
    }
}
