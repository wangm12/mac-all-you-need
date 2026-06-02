import AppKit
import SwiftUI

// MARK: - Tab content router

struct DockFunctionTabContent: View {
    let tab: DockFunctionTab
    @Binding var hub: DockHubSettings
    var onSettingsChanged: (() -> Void)?

    var body: some View {
        switch tab {
        case .permissions:
            DockSettingsTabPermissions(hub: $hub, onSettingsChanged: onSettingsChanged)
        case .features:
            DockSettingsTabDock(hub: $hub, onSettingsChanged: onSettingsChanged)
        case .previews:
            DockSettingsTabPreviews(hub: $hub, onSettingsChanged: onSettingsChanged)
        case .switcher:
            DockSettingsTabSwitcher(hub: $hub, onSettingsChanged: onSettingsChanged)
        case .cmdTab:
            DockSettingsTabCmdTab(hub: $hub, onSettingsChanged: onSettingsChanged)
        case .locking:
            DockSettingsTabLocking(hub: $hub, onSettingsChanged: onSettingsChanged)
        case .customize:
            DockSettingsTabCustomizations(hub: $hub, onSettingsChanged: onSettingsChanged)
        }
    }
}

// MARK: - Full settings page (feature registry / onboarding)

struct DockPreviewSettingsView: View {
    var onSettingsChanged: (() -> Void)?
    @State private var tab: DockFunctionTab = .features

    var body: some View {
        MAYNSettingsPage(
            title: "Dock",
            subtitle: "Window previews, switcher, Cmd+Tab enhancements, dock locking, and active indicator."
        ) {
            VStack(alignment: .leading, spacing: 16) {
                FunctionSegmentedTabStrip(
                    selection: tab,
                    fillsAvailableWidth: true,
                    size: .control
                ) { selected in
                    tab = selected
                }
                DockSettingsPageBody(tab: tab, onSettingsChanged: onSettingsChanged)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }
}
