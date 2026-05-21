import Core
import SwiftUI

struct WindowLayoutsMainPage: View {
    let controller: AppController
    @State private var settings = WindowControlSettingsStore.load()
    @State private var hotkeyMap = HotkeyMapStore.defaultMap
    @AppStorage(WindowLayoutsFunctionTab.storageKey, store: AppGroupSettings.defaults)
    private var selectedTabRaw = WindowLayoutsFunctionTab.defaultTab.rawValue

    private var selectedTab: Binding<WindowLayoutsFunctionTab> {
        Binding {
            WindowLayoutsFunctionTab.storedSelection(selectedTabRaw)
        } set: {
            selectedTabRaw = $0.rawValue
        }
    }

    var body: some View {
        FunctionPageShell(
            title: "Window Layouts",
            subtitle: "Arrange, snap, and restore windows.",
            selection: selectedTab,
            content: {
                FunctionPageScrollContent {
                    WindowControlSettingsView(
                        controller: controller,
                        settings: $settings,
                        hotkeyMap: $hotkeyMap,
                        scope: scope(for: selectedTab.wrappedValue)
                    )
                }
            }
        )
        .onAppear(perform: reloadState)
    }

    private func scope(for tab: WindowLayoutsFunctionTab) -> WindowControlSettingsScope {
        switch tab {
        case .shortcuts: .layoutsShortcuts
        case .snap: .layoutsSnap
        case .apps: .layoutsApps
        }
    }

    private func reloadState() {
        settings = WindowControlSettingsStore.load()
        hotkeyMap = HotkeyMapStore.load()
    }
}

struct GrabAnywhereMainPage: View {
    let controller: AppController
    @State private var settings = WindowControlSettingsStore.load()
    @State private var hotkeyMap = HotkeyMapStore.defaultMap
    @AppStorage(WindowGrabFunctionTab.storageKey, store: AppGroupSettings.defaults)
    private var selectedTabRaw = WindowGrabFunctionTab.defaultTab.rawValue

    private var selectedTab: Binding<WindowGrabFunctionTab> {
        Binding {
            WindowGrabFunctionTab.storedSelection(selectedTabRaw)
        } set: {
            selectedTabRaw = $0.rawValue
        }
    }

    var body: some View {
        FunctionPageShell(
            title: "Window Grab",
            subtitle: "Hold a modifier and drag windows from any visible area.",
            selection: selectedTab,
            content: {
                FunctionPageScrollContent {
                    WindowControlSettingsView(
                        controller: controller,
                        settings: $settings,
                        hotkeyMap: $hotkeyMap,
                        scope: scope(for: selectedTab.wrappedValue)
                    )
                }
            }
        )
        .onAppear(perform: reloadState)
    }

    private func scope(for tab: WindowGrabFunctionTab) -> WindowControlSettingsScope {
        switch tab {
        case .gesture: .grabGesture
        case .apps: .grabApps
        }
    }

    private func reloadState() {
        settings = WindowControlSettingsStore.load()
        hotkeyMap = HotkeyMapStore.load()
    }
}

enum WindowControlActionPresentation {
    static func editRoute(for action: HotkeyAction) -> MainAppDestination {
        .windowLayouts
    }
}
