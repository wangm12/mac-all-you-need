import SwiftUI

struct DockSettingsTabDock: View {
    @Binding var hub: DockHubSettings
    var onSettingsChanged: (() -> Void)?

    private var settings: DockSettingsHubBindings {
        DockSettingsHubBindings(hub: $hub, onSettingsChanged: onSettingsChanged)
    }

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        featureGrid
    }

    private var featureGrid: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
            ForEach(features) { feature in
                DockFeatureToggleCard(
                    title: feature.title,
                    subtitle: feature.subtitle,
                    symbolName: feature.symbolName,
                    accent: feature.accent,
                    isOn: Binding(
                        get: { hub[keyPath: feature.keyPath] },
                        set: { hub[keyPath: feature.keyPath] = $0; settings.persist() }
                    )
                )
            }
        }
    }
}

private struct DockMasterFeatureItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let symbolName: String
    let accent: Color
    let keyPath: WritableKeyPath<DockHubSettings, Bool>
}

private let features: [DockMasterFeatureItem] = [
    DockMasterFeatureItem(
        id: "dock-previews",
        title: "Dock hover previews",
        subtitle: "Show window thumbnails when hovering a Dock icon.",
        symbolName: "rectangle.on.rectangle",
        accent: .blue,
        keyPath: \.master.enableDockPreviews
    ),
    DockMasterFeatureItem(
        id: "window-switcher",
        title: "Window switcher",
        subtitle: "Alt+Tab–style switcher with configurable keybinds.",
        symbolName: "square.grid.2x2",
        accent: .purple,
        keyPath: \.master.enableWindowSwitcher
    ),
    DockMasterFeatureItem(
        id: "cmd-tab",
        title: "Cmd+Tab enhancements",
        subtitle: "Show window previews while holding Command.",
        symbolName: "command",
        accent: .orange,
        keyPath: \.master.enableCmdTabEnhancements
    ),
    DockMasterFeatureItem(
        id: "dock-locking",
        title: "Dock locking",
        subtitle: "Keep the Dock on a specific display.",
        symbolName: "lock.rectangle",
        accent: .teal,
        keyPath: \.master.enableDockLocking
    ),
    DockMasterFeatureItem(
        id: "active-indicator",
        title: "Active app indicator",
        subtitle: "Colored bar beneath the active Dock icon.",
        symbolName: "minus.rectangle",
        accent: .pink,
        keyPath: \.master.enableActiveAppIndicator
    ),
]
