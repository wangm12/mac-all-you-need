import AppKit
import SwiftUI

struct DockSettingsTabLocking: View {
    var onSettingsChanged: (() -> Void)?
    @State private var hub = DockHubSettingsStore.load()

    var body: some View {
        Group {
            generalSection
            if hub.master.enableDockLocking {
                configurationSection
            }
            infoSection
        }
        .onAppear { hub = DockHubSettingsStore.load() }
    }

    private func persist() {
        DockHubSettingsStore.save(hub)
        onSettingsChanged?()
    }

    private var generalSection: some View {
        MAYNSection(title: "General") {
            MAYNSettingsRow(title: "Lock Dock to screen", subtitle: "Prevent the Dock from jumping to other displays on multi-monitor setups.") {
                Toggle("", isOn: Binding(
                    get: { hub.master.enableDockLocking },
                    set: { hub.master.enableDockLocking = $0; persist() }
                )).labelsHidden()
            }
        }
    }

    private var configurationSection: some View {
        MAYNSection(title: "Configuration") {
            MAYNSettingsRow(title: "Lock Dock to", subtitle: "The display that the Dock stays on.") {
                MAYNDropdown(
                    selection: Binding(
                        get: { hub.dockLock.lockedScreenIdentifier ?? "" },
                        set: { hub.dockLock.lockedScreenIdentifier = $0.isEmpty ? nil : $0; persist() }
                    ),
                    options: screenOptions.map(\.id)
                ) { id in
                    screenOptions.first(where: { $0.id == id })?.name ?? id
                }
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Bypass modifier key", subtitle: "Hold this key to temporarily allow the Dock to move to another display.") {
                MAYNDropdown(selection: Binding(
                    get: { hub.dockLock.overrideModifier },
                    set: { hub.dockLock.overrideModifier = $0; persist() }
                ), options: DockLockOverrideModifier.allCases) { $0.displayName }
            }
        }
    }

    private var infoSection: some View {
        MAYNSection(title: "Requirements") {
            MAYNSettingsRow(
                title: "Displays have separate Spaces",
                subtitle: "Enable 'Displays have separate Spaces' in System Settings → Desktop & Dock for Dock locking to work correctly."
            ) {
                EmptyView()
            }
        }
    }

    private struct ScreenOption {
        let id: String
        let name: String
    }

    private var screenOptions: [ScreenOption] {
        NSScreen.screens.compactMap { screen -> ScreenOption? in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            return ScreenOption(id: number.stringValue, name: screen.localizedName)
        }
    }
}
