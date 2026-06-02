import AppKit
import SwiftUI

struct DockSettingsTabSwitcher: View {
    @Binding var hub: DockHubSettings
    var onSettingsChanged: (() -> Void)?

    private var settings: DockSettingsHubBindings {
        DockSettingsHubBindings(hub: $hub, onSettingsChanged: onSettingsChanged)
    }

    var body: some View {
        Group {
            if !hub.master.enableWindowSwitcher {
                disabledHint
            }
            generalSection
            DockAdvancedSettingsDisclosure {
                mouseAdvancedSection
                filteringAdvancedSection
                searchSection
                sortingSection
                placementSection
                appearanceSection
                trafficLightsSection
                keybindsSection
                fullscreenBlacklistSection
            }
        }
    }

    private var disabledHint: some View {
        InstructionStrip(
            text: "Window switcher is off. Enable it on the Features tab to use these settings.",
            symbol: "square.grid.2x2"
        )
    }

    // MARK: General

    private var generalSection: some View {
        MAYNSection(title: "General") {
            MAYNSettingsRow(title: "Show instantly", subtitle: "Display the switcher immediately without a delay.") {
                Toggle("", isOn: settings.bool(\.switcher.instantSwitcher)).labelsHidden()
                    .disabled(!hub.master.enableWindowSwitcher)
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Release key to select", subtitle: "Release the initializer key to select the highlighted window.") {
                Toggle("", isOn: Binding(
                    get: { !hub.switcher.preventSwitcherHide },
                    set: { hub.switcher.preventSwitcherHide = !$0; settings.persist() }
                )).labelsHidden()
                .disabled(!hub.master.enableWindowSwitcher)
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Start on second window", subtitle: "Classic alt+tab ordering — begin selection on the second window.") {
                Toggle("", isOn: settings.bool(\.switcher.useClassicWindowOrdering)).labelsHidden()
                    .disabled(!hub.master.enableWindowSwitcher)
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Enable mouse hover selection", subtitle: "Highlight the window under the mouse cursor.") {
                Toggle("", isOn: settings.bool(\.switcher.enableMouseHover)).labelsHidden()
                    .disabled(!hub.master.enableWindowSwitcher)
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Current Space only", subtitle: "Only show windows on the active desktop Space.") {
                Toggle("", isOn: settings.bool(\.switcher.currentSpaceOnly)).labelsHidden()
                    .disabled(!hub.master.enableWindowSwitcher)
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Current monitor only", subtitle: "Only show windows on the display with the switcher.") {
                Toggle("", isOn: settings.bool(\.switcher.currentMonitorOnly)).labelsHidden()
                    .disabled(!hub.master.enableWindowSwitcher)
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Include hidden windows", subtitle: "Show minimized and hidden windows.") {
                Toggle("", isOn: settings.bool(\.switcher.includeHiddenWindows)).labelsHidden()
                    .disabled(!hub.master.enableWindowSwitcher)
            }
        }
    }

    private var mouseAdvancedSection: some View {
        MAYNSection(title: "Mouse") {
            MAYNSettingsRow(title: "Mouse follows focus", subtitle: "Move the mouse cursor to the focused window.") {
                MAYNDropdown(selection: settings.value(\.switcher.mouseFollowsFocus), options: DockSwitcherMouseFollowsFocus.allCases) { $0.displayName }
            }
            if hub.switcher.enableMouseHover {
                MAYNDivider()
                MAYNSettingsRow(title: "Auto-scroll speed", subtitle: "Speed of auto-scrolling when the mouse is at the container edge.") {
                    MAYNNumericStepper(text: "Speed", value: settings.roundedInt(from:\.switcher.mouseHoverAutoScrollSpeed), range: 1...10, step: 1, presets: [2, 4, 6, 8, 10], suffix: "")
                }
            }
        }
    }

    private var filteringAdvancedSection: some View {
        MAYNSection(title: "Filtering") {
            MAYNSettingsRow(title: "Limit to active app", subtitle: "Only show windows from the frontmost application.") {
                Toggle("", isOn: settings.bool(\.switcher.limitToFrontmostApp)).labelsHidden()
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Show windowless apps", subtitle: "Show running apps even when they have no open windows.") {
                Toggle("", isOn: settings.bool(\.switcher.showWindowlessApps)).labelsHidden()
            }
        }
    }

    // MARK: Search

    private var searchSection: some View {
        MAYNSection(title: "Search") {
            MAYNSettingsRow(title: "Enable search", subtitle: "Type to filter windows by name.") {
                Toggle("", isOn: settings.bool(\.switcher.enableSearch)).labelsHidden()
            }
            if hub.switcher.enableSearch {
                MAYNDivider()
                MAYNSettingsRow(title: "Focus search on open", subtitle: "Automatically focus the search field when the switcher opens.") {
                    Toggle("", isOn: settings.bool(\.switcher.focusSearchOnOpen)).labelsHidden()
                }
                MAYNDivider()
                MAYNSettingsRow(title: "Search fuzziness", subtitle: "How loosely the search matches (1 = strict, 5 = loose).") {
                    MAYNNumericStepper(text: "Fuzziness", value: settings.int(\.switcher.searchFuzziness), range: 1...5, step: 1, presets: [1, 2, 3, 4, 5], suffix: "")
                }
            }
        }
    }

    // MARK: Sorting

    private var sortingSection: some View {
        MAYNSection(title: "Sorting") {
            MAYNSettingsRow(title: "Window sort order", subtitle: "Order of windows in the switcher.") {
                MAYNDropdown(selection: settings.value(\.switcher.sortOrder), options: DockSortOrder.allCases) { $0.displayName }
            }
        }
    }

    // MARK: Placement

    private var placementSection: some View {
        MAYNSection(title: "Placement") {
            MAYNSettingsRow(title: "Screen", subtitle: "Which screen to display the switcher on.") {
                MAYNDropdown(selection: settings.value(\.switcher.placementStrategy), options: DockSwitcherPlacementStrategy.allCases) { $0.displayName }
            }
            if hub.switcher.placementStrategy == .pinnedToScreen {
                MAYNDivider()
                MAYNSettingsRow(title: "Pinned screen", subtitle: "The screen to always show the switcher on.") {
                    MAYNDropdown(selection: settings.value(\.switcher.pinnedScreenIdentifier), options: screenOptions.map(\.id)) {
                        screenOptions.first(where: { $0.id == $0.id })?.name ?? $0 ?? "None"
                    }
                }
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Offset position", subtitle: "Shift the switcher panel from its default position.") {
                Toggle("", isOn: settings.bool(\.switcher.enableOffsetPlacement)).labelsHidden()
            }
            if hub.switcher.enableOffsetPlacement {
                MAYNDivider()
                MAYNSettingsRow(title: "Anchor to top", subtitle: "Anchor the switcher to the top edge of the screen.") {
                    Toggle("", isOn: settings.bool(\.switcher.anchorToTop)).labelsHidden()
                }
                MAYNDivider()
                MAYNSettingsRow(title: "Vertical offset", subtitle: "Vertical position as a percentage of screen height.") {
                    MAYNNumericStepper(text: "V offset", value: settings.roundedInt(from:\.switcher.verticalOffsetPercent), range: -80...80, step: 5, presets: [-40, 0, 40], suffix: "%")
                }
                MAYNDivider()
                MAYNSettingsRow(title: "Horizontal offset", subtitle: "Horizontal position as a percentage of screen width.") {
                    MAYNNumericStepper(text: "H offset", value: settings.roundedInt(from:\.switcher.horizontalOffsetPercent), range: -80...80, step: 5, presets: [-40, 0, 40], suffix: "%")
                }
            }
        }
    }

    // MARK: Appearance

    private var appearanceSection: some View {
        MAYNSection(title: "Appearance") {
            MAYNSettingsRow(title: "Show app header", subtitle: "Display the app name and icon above the window list.") {
                Toggle("", isOn: settings.bool(\.switcher.showAppHeader)).labelsHidden()
            }
            if hub.switcher.showAppHeader {
                MAYNDivider()
                MAYNSettingsRow(title: "App icon size", subtitle: "Size of app icons in the header (0 = automatic).") {
                    MAYNNumericStepper(text: "Icon", value: settings.roundedInt(from:\.switcher.appIconSize), range: 0...64, step: 4, presets: [0, 16, 24, 32, 48], suffix: "pt")
                }
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Control position", subtitle: "Where to show window title and traffic lights.") {
                MAYNDropdown(selection: settings.value(\.switcher.controlPosition), options: DockPreviewControlPosition.allCases) { positionLabel($0) }
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Show window title", subtitle: "Display the window name below each preview card.") {
                Toggle("", isOn: settings.bool(\.switcher.showWindowTitle)).labelsHidden()
            }
            if hub.switcher.showWindowTitle {
                MAYNDivider()
                MAYNSettingsRow(title: "Title visibility", subtitle: "When to show the window title.") {
                    MAYNDropdown(selection: settings.value(\.switcher.windowTitleVisibility), options: DockWindowTitleVisibilityMode.allCases) { $0.displayName }
                }
                MAYNDivider()
                MAYNSettingsRow(title: "Disable dock styling on titles", subtitle: "Remove the Dock-style styling from window titles.") {
                    Toggle("", isOn: settings.bool(\.switcher.disableDockStyleTrafficLights)).labelsHidden()
                }
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Embed controls in frames", subtitle: "Overlay controls inside the preview frames instead of outside.") {
                Toggle("", isOn: settings.bool(\.switcher.useEmbeddedElements)).labelsHidden()
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Scroll direction", subtitle: "Direction of the window list when there are many items.") {
                MAYNDropdown(selection: settings.value(\.switcher.scrollDirection), options: DockSwitcherScrollDirection.allCases) { $0.displayName }
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Max rows", subtitle: "Maximum number of rows (or columns in horizontal mode).") {
                MAYNNumericStepper(text: "Rows", value: settings.int(\.switcher.maxRows), range: 1...8, step: 1, presets: [2, 3, 4, 6, 8], suffix: "")
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Ignore screen size limit", subtitle: "Allow the switcher to extend beyond the screen edge.") {
                Toggle("", isOn: settings.bool(\.switcher.ignoreScreenLimit)).labelsHidden()
            }
        }
    }

    // MARK: Traffic lights

    private var trafficLightsSection: some View {
        MAYNSection(title: "Traffic light buttons") {
            MAYNSettingsRow(title: "Visibility", subtitle: "When close/minimize/fullscreen buttons appear on windows.") {
                MAYNDropdown(selection: settings.value(\.switcher.trafficLightVisibility), options: DockTrafficLightVisibilityMode.allCases) { $0.displayName }
            }
            if hub.switcher.trafficLightVisibility != .never {
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
                    Toggle("", isOn: settings.bool(\.switcher.useMonochromeTrafficLights)).labelsHidden()
                }
                MAYNDivider()
                MAYNSettingsRow(title: "Disable dock styling", subtitle: "Remove the Dock-style styling from buttons.") {
                    Toggle("", isOn: settings.bool(\.switcher.disableDockStyleTrafficLights)).labelsHidden()
                }
            }
        }
    }

    // MARK: Keybinds

    private var keybindsSection: some View {
        MAYNSection(title: "Keyboard") {
            MAYNSettingsRow(title: "Vim motions", subtitle: "Use H/J/K/L keys to navigate windows.") {
                Toggle("", isOn: settings.bool(\.switcher.enableVimMotions)).labelsHidden()
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Pass arrow keys through", subtitle: "Let arrow key presses reach the focused app.") {
                Toggle("", isOn: settings.bool(\.switcher.passArrowsThrough)).labelsHidden()
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Require ⇧+key to go back", subtitle: "Use Shift+trigger key to cycle backwards through windows.") {
                Toggle("", isOn: settings.bool(\.switcher.requireShiftToGoBack)).labelsHidden()
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Alternate shortcut mode", subtitle: "Behavior when the alternate shortcut is used.") {
                MAYNDropdown(selection: settings.value(\.switcher.alternateShortcutMode), options: DockSwitcherInvocationMode.allCases) { $0.displayName }
            }
        }
    }

    // MARK: Fullscreen blacklist

    private var fullscreenBlacklistSection: some View {
        MAYNSection(title: "Fullscreen app blacklist") {
            if hub.switcher.fullscreenAppBlacklist.isEmpty {
                MAYNSettingsRow(title: "No apps excluded", subtitle: "The switcher will be shown for all fullscreen apps.") {
                    EmptyView()
                }
            } else {
                ForEach(Array(hub.switcher.fullscreenAppBlacklist.enumerated()), id: \.offset) { idx, name in
                    MAYNSettingsRow(title: name, subtitle: nil) {
                        MAYNButton("Remove", role: .destructive) {
                            hub.switcher.fullscreenAppBlacklist.remove(at: idx)
                            settings.persist()
                        }
                    }
                    if idx < hub.switcher.fullscreenAppBlacklist.count - 1 {
                        MAYNDivider()
                    }
                }
            }
        }
    }

    // MARK: Helpers

    private struct ScreenOption {
        let id: String?
        let name: String
    }

    private var screenOptions: [ScreenOption] {
        NSScreen.screens.map { screen in
            let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? String
            return ScreenOption(id: id, name: screen.localizedName)
        }
    }

    private func positionLabel(_ position: DockPreviewControlPosition) -> String {
        position.rawValue
            .replacingOccurrences(of: "([A-Z])", with: " $1", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
            .capitalized
    }

    private func trafficLightToggle(_ action: DockPreviewWindowAction) -> Binding<Bool> {
        Binding(
            get: { hub.switcher.enabledTrafficLightButtons.contains(action) },
            set: { enabled in
                if enabled { hub.switcher.enabledTrafficLightButtons.insert(action) }
                else { hub.switcher.enabledTrafficLightButtons.remove(action) }
                settings.persist()
            }
        )
    }
}
