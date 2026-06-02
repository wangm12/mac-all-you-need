import SwiftUI

struct DockSettingsTabCmdTab: View {
    var onSettingsChanged: (() -> Void)?
    @State private var hub = DockHubSettingsStore.load()

    var body: some View {
        Group {
            generalSection
            filteringSection
            appearanceSection
            trafficLightsSection
        }
        .onAppear { hub = DockHubSettingsStore.load() }
    }

    private func persist() {
        DockHubSettingsStore.save(hub)
        onSettingsChanged?()
    }

    // MARK: General

    private var generalSection: some View {
        MAYNSection(title: "General") {
            MAYNSettingsRow(title: "Enable Cmd+Tab enhancements", subtitle: "Intercept Cmd+Tab to show window previews instead of the system switcher.") {
                Toggle("", isOn: boolBinding(\.master.enableCmdTabEnhancements)).labelsHidden()
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Automatically select first window", subtitle: "Select the first window when Cmd+Tab is pressed.") {
                Toggle("", isOn: boolBinding(\.cmdTab.autoSelectFirstWindow)).labelsHidden()
            }
        }
    }

    // MARK: Filtering

    private var filteringSection: some View {
        MAYNSection(title: "Filtering") {
            MAYNSettingsRow(title: "Current Space only", subtitle: "Only show windows on the active desktop Space.") {
                Toggle("", isOn: boolBinding(\.cmdTab.currentSpaceOnly)).labelsHidden()
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Current monitor only", subtitle: "Only show windows on the current display.") {
                Toggle("", isOn: boolBinding(\.cmdTab.currentMonitorOnly)).labelsHidden()
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Include hidden windows", subtitle: "Show minimized and hidden windows.") {
                Toggle("", isOn: boolBinding(\.cmdTab.includeHiddenWindows)).labelsHidden()
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Show windowless apps", subtitle: "Show running apps even when they have no open windows.") {
                Toggle("", isOn: boolBinding(\.cmdTab.showWindowlessApps)).labelsHidden()
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Ignore single-window apps", subtitle: "Hide apps that have only one window.") {
                Toggle("", isOn: boolBinding(\.cmdTab.ignoreAppsWithSingleWindow)).labelsHidden()
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Window sort order", subtitle: "Order of windows in the Cmd+Tab panel.") {
                MAYNDropdown(selection: binding(\.cmdTab.sortOrder), options: DockSortOrder.allCases) { $0.displayName }
            }
        }
    }

    // MARK: Appearance

    private var appearanceSection: some View {
        MAYNSection(title: "Appearance") {
            MAYNSettingsRow(title: "Show app header", subtitle: "Display the app name and icon above the window list.") {
                Toggle("", isOn: boolBinding(\.cmdTab.showAppName)).labelsHidden()
            }
            if hub.cmdTab.showAppName {
                MAYNDivider()
                MAYNSettingsRow(title: "App header style", subtitle: "Visual style for the app header.") {
                    MAYNDropdown(selection: binding(\.cmdTab.appNameStyle), options: DockCmdTabAppNameStyle.allCases) { $0.displayName }
                }
                MAYNDivider()
                MAYNSettingsRow(title: "Show app icon only", subtitle: "Show only the app icon without the name.") {
                    Toggle("", isOn: boolBinding(\.cmdTab.showAppIconOnly)).labelsHidden()
                }
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Control position", subtitle: "Where to show window title and traffic lights.") {
                MAYNDropdown(selection: binding(\.cmdTab.controlPosition), options: DockPreviewControlPosition.allCases) { positionLabel($0) }
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Show window title", subtitle: "Display the window name on each preview card.") {
                Toggle("", isOn: boolBinding(\.cmdTab.showWindowTitle)).labelsHidden()
            }
            if hub.cmdTab.showWindowTitle {
                MAYNDivider()
                MAYNSettingsRow(title: "Title visibility", subtitle: "When to show the window title.") {
                    MAYNDropdown(selection: binding(\.cmdTab.windowTitleVisibility), options: DockWindowTitleVisibilityMode.allCases) { $0.displayName }
                }
                MAYNDivider()
                MAYNSettingsRow(title: "Title position", subtitle: "Where to display the window title.") {
                    MAYNDropdown(selection: binding(\.cmdTab.windowTitlePosition), options: DockWindowTitlePosition.allCases) { $0.displayName }
                }
                MAYNDivider()
                MAYNSettingsRow(title: "Disable dock styling on titles", subtitle: "Remove the Dock-style styling from window titles.") {
                    Toggle("", isOn: boolBinding(\.cmdTab.disableDockStyleTitles)).labelsHidden()
                }
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Embed controls in frames", subtitle: "Overlay controls inside the preview frames instead of outside.") {
                Toggle("", isOn: boolBinding(\.cmdTab.useEmbeddedElements)).labelsHidden()
            }
        }
    }

    // MARK: Traffic lights

    private var trafficLightsSection: some View {
        MAYNSection(title: "Traffic light buttons") {
            MAYNSettingsRow(title: "Visibility", subtitle: "When close/minimize/fullscreen buttons appear on windows.") {
                MAYNDropdown(selection: binding(\.cmdTab.trafficLightVisibility), options: DockTrafficLightVisibilityMode.allCases) { $0.displayName }
            }
            if hub.cmdTab.trafficLightVisibility != .never {
                MAYNDivider()
                MAYNSettingsRow(title: "Button position", subtitle: "Where to show the traffic light buttons.") {
                    MAYNDropdown(selection: binding(\.cmdTab.trafficLightPosition), options: DockTrafficLightPosition.allCases) { $0.displayName }
                }
                MAYNDivider()
                MAYNSettingsRow(title: "Close", subtitle: nil) {
                    Toggle("", isOn: trafficLightToggle(.close)).labelsHidden()
                }
                MAYNDivider()
                MAYNSettingsRow(title: "Minimize", subtitle: nil) {
                    Toggle("", isOn: trafficLightToggle(.minimize)).labelsHidden()
                }
                MAYNDivider()
                MAYNSettingsRow(title: "Fullscreen", subtitle: nil) {
                    Toggle("", isOn: trafficLightToggle(.toggleFullScreen)).labelsHidden()
                }
                MAYNDivider()
                MAYNSettingsRow(title: "Quit", subtitle: nil) {
                    Toggle("", isOn: trafficLightToggle(.quit)).labelsHidden()
                }
                MAYNDivider()
                MAYNSettingsRow(title: "Monochrome style", subtitle: "Show traffic light buttons in a single color.") {
                    Toggle("", isOn: boolBinding(\.cmdTab.useMonochromeTrafficLights)).labelsHidden()
                }
                MAYNDivider()
                MAYNSettingsRow(title: "Disable dock styling", subtitle: "Remove Dock-style styling from buttons.") {
                    Toggle("", isOn: boolBinding(\.cmdTab.disableDockStyleTrafficLights)).labelsHidden()
                }
            }
        }
    }

    // MARK: Helpers

    private func positionLabel(_ position: DockPreviewControlPosition) -> String {
        position.rawValue
            .replacingOccurrences(of: "([A-Z])", with: " $1", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
            .capitalized
    }

    private func trafficLightToggle(_ action: DockPreviewWindowAction) -> Binding<Bool> {
        Binding(
            get: { hub.cmdTab.enabledTrafficLightButtons.contains(action) },
            set: { enabled in
                if enabled { hub.cmdTab.enabledTrafficLightButtons.insert(action) }
                else { hub.cmdTab.enabledTrafficLightButtons.remove(action) }
                persist()
            }
        )
    }

    private func boolBinding(_ keyPath: WritableKeyPath<DockHubSettings, Bool>) -> Binding<Bool> {
        Binding(get: { hub[keyPath: keyPath] }, set: { hub[keyPath: keyPath] = $0; persist() })
    }

    private func binding<T>(_ keyPath: WritableKeyPath<DockHubSettings, T>) -> Binding<T> {
        Binding(get: { hub[keyPath: keyPath] }, set: { hub[keyPath: keyPath] = $0; persist() })
    }
}
