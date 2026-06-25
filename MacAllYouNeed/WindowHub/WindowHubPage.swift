import ApplicationServices
import Core
import FeatureCore
import Platform
import SwiftUI

struct WindowHubPage: View {
    let controller: AppController
    @State private var settings = WindowHubSettingsStore.load()
    @State private var hotkeyMap = HotkeyMapStore.load()
    @AppStorage(WindowHubFunctionTab.storageKey, store: AppGroupSettings.defaults)
    private var selectedTabRaw = WindowHubFunctionTab.settings.rawValue

    private var selectedTab: Binding<WindowHubFunctionTab> {
        Binding {
            WindowHubFunctionTab.storedSelection(selectedTabRaw)
        } set: {
            selectedTabRaw = $0.rawValue
        }
    }

    var body: some View {
        FunctionPageShell(
            title: "Windows",
            subtitle: "Search apps, windows, and tabs from a lightweight floating panel.",
            tabs: [WindowHubFunctionTab.settings],
            selection: selectedTab,
            toolbar: {
                MainHeaderShortcutDisplay(
                    text: MainHotkeyPresentation.display(for: .windowHub, in: hotkeyMap),
                    issueMessage: windowHubHeaderHotkeyIssue
                )
            },
            content: {
                FunctionPageScrollContent {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Search first, then organize")
                            .font(.headline.weight(.semibold))
                        Text("Use the floating panel to search apps, windows, and tabs. Open the full page here for panel settings, Accessibility status, and AI organize controls.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    WindowHubSettingsView(
                        controller: controller,
                        settings: $settings,
                        hotkeyMap: $hotkeyMap
                    ) {
                        controller.windowHubReloadSettings()
                    }
                }
            }
        )
        .onAppear {
            settings = WindowHubSettingsStore.load()
            hotkeyMap = HotkeyMapStore.load()
        }
    }

    private var windowHubHeaderHotkeyIssue: String? {
        let descriptors = hotkeyMap[.windowHub] ?? HotkeyAction.windowHub.defaultDescriptors
        guard let descriptor = descriptors.first ?? HotkeyAction.windowHub.primaryDefaultDescriptor else {
            return nil
        }
        return HotkeyValidation.issue(
            forAppHotkey: descriptor,
            action: .windowHub,
            index: 0,
            appHotkeys: hotkeyMap,
            voiceShortcut: VoiceActivationSettingsStore.load().shortcut,
            dockShortcuts: HotkeyValidation.liveDockShortcuts()
        )?.message
    }
}

enum WindowHubFunctionTab: String, FunctionTabDestination {
    case settings

    static let storageKey = "main.windowHub.selectedTab"
    static let defaultTab = WindowHubFunctionTab.settings

    var title: String { "Settings" }
    var symbolName: String { "slider.horizontal.3" }
}
