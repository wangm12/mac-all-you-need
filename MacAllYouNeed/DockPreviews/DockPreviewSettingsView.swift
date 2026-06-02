import AppKit
import SwiftUI

// MARK: - Tab content router

struct DockFunctionTabContent: View {
    let tab: DockFunctionTab
    var onSettingsChanged: (() -> Void)?

    var body: some View {
        switch tab {
        case .permissions:
            DockSettingsTabPermissions()
        case .features:
            DockSettingsTabDock(onSettingsChanged: onSettingsChanged)
        case .previews:
            DockSettingsTabPreviews(onSettingsChanged: onSettingsChanged)
        case .switcher:
            DockSettingsTabSwitcher(onSettingsChanged: onSettingsChanged)
        case .cmdTab:
            DockSettingsTabCmdTab(onSettingsChanged: onSettingsChanged)
        case .locking:
            DockSettingsTabLocking(onSettingsChanged: onSettingsChanged)
        case .customize:
            DockSettingsTabCustomizations(onSettingsChanged: onSettingsChanged)
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
                DockFunctionTabContent(tab: tab, onSettingsChanged: onSettingsChanged)
            }
        }
    }
}
