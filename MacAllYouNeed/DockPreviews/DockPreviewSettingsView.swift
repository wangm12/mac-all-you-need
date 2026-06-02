import AppKit
import SwiftUI

// MARK: - Tab enum

enum DockSettingsTab: String, CaseIterable, SegmentedTabDestination {
    case dock = "Dock"
    case previews = "Dock Previews"
    case switcher = "Window Switcher"
    case cmdTab = "Command Tab"
    case locking = "Dock Locking"
    case customizations = "Customizations"

    var title: String { rawValue }
    var symbolName: String {
        switch self {
        case .dock: "dock.rectangle"
        case .previews: "rectangle.on.rectangle"
        case .switcher: "square.grid.2x2"
        case .cmdTab: "command"
        case .locking: "lock.rectangle"
        case .customizations: "slider.horizontal.3"
        }
    }
}

// MARK: - Inner tab content (no MAYNSettingsPage wrapper — used both in sidebar and function page)

struct DockSettingsTabContent: View {
    var onSettingsChanged: (() -> Void)?
    @State private var tab: DockSettingsTab = .dock

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            FunctionSegmentedTabStrip(
                selection: tab,
                fillsAvailableWidth: true,
                size: .control
            ) { selected in
                tab = selected
            }

            switch tab {
            case .dock:
                DockSettingsTabDock(onSettingsChanged: onSettingsChanged)
            case .previews:
                DockSettingsTabPreviews(onSettingsChanged: onSettingsChanged)
            case .switcher:
                DockSettingsTabSwitcher(onSettingsChanged: onSettingsChanged)
            case .cmdTab:
                DockSettingsTabCmdTab(onSettingsChanged: onSettingsChanged)
            case .locking:
                DockSettingsTabLocking(onSettingsChanged: onSettingsChanged)
            case .customizations:
                DockSettingsTabCustomizations(onSettingsChanged: onSettingsChanged)
            }
        }
    }
}

// MARK: - Full settings page (used by Settings sidebar entry)

struct DockPreviewSettingsView: View {
    var onSettingsChanged: (() -> Void)?

    var body: some View {
        MAYNSettingsPage(
            title: "Dock",
            subtitle: "Window previews, switcher, Cmd+Tab enhancements, dock locking, and active indicator."
        ) {
            DockSettingsTabContent(onSettingsChanged: onSettingsChanged)
        }
    }
}
