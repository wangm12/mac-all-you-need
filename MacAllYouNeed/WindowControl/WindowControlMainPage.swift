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
            toolbar: {
                StatusPill(
                    text: WindowControlActionPresentation.statusText(
                        for: controller.windowControl.state,
                        featureEnabled: controller.windowControl.windowLayoutsEnabled
                    ),
                    kind: WindowControlActionPresentation.statusKind(
                        for: controller.windowControl.state,
                        featureEnabled: controller.windowControl.windowLayoutsEnabled
                    )
                )
            },
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
        case .radial: .layoutsRadial
        case .snap: .layoutsSnap
        case .apps: .layoutsApps
        case .rules: .layoutsRules
        case .diagnostics: .advanced
        }
    }

    private func reloadState() {
        settings = WindowControlSettingsStore.load()
        hotkeyMap = HotkeyMapStore.load()
    }
}

struct GrabAnywhereMainPage: View {
    @Bindable var controller: AppController
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
            toolbar: {
                StatusPill(
                    text: WindowControlActionPresentation.statusText(
                        for: controller.windowControl.state,
                        featureEnabled: controller.windowControl.windowGrabEnabled
                    ),
                    kind: WindowControlActionPresentation.statusKind(
                        for: controller.windowControl.state,
                        featureEnabled: controller.windowControl.windowGrabEnabled
                    )
                )
            },
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
        .onAppear {
            reloadState()
            controller.windowControl.reloadSettings()
        }
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
    static func statusText(
        for state: WindowControlCoordinator.State,
        featureEnabled: Bool
    ) -> String {
        guard featureEnabled else { return "Off" }
        return runtimeStatusText(for: state)
    }

    static func statusKind(
        for state: WindowControlCoordinator.State,
        featureEnabled: Bool
    ) -> StatusPill.Kind {
        guard featureEnabled else { return .neutral }
        return runtimeStatusKind(for: state)
    }

    /// Dashboard tiles hide the pill only when the gesture is enabled and the tap is active.
    static func dashboardStatusText(
        for state: WindowControlCoordinator.State,
        featureEnabled: Bool,
        gestureEnabled: Bool,
        axTrusted: Bool
    ) -> String? {
        guard featureEnabled, gestureEnabled else { return "Off" }
        guard axTrusted else { return "Needs Accessibility" }
        switch state {
        case .active:
            return nil
        case .needsAccessibility:
            return "Needs Accessibility"
        case .off:
            return "Off"
        case .suspended:
            return "Suspended"
        case .error:
            return "Error"
        }
    }

    static func dashboardStatusKind(
        for state: WindowControlCoordinator.State,
        featureEnabled: Bool,
        gestureEnabled: Bool,
        axTrusted: Bool
    ) -> StatusPill.Kind? {
        guard let text = dashboardStatusText(
            for: state,
            featureEnabled: featureEnabled,
            gestureEnabled: gestureEnabled,
            axTrusted: axTrusted
        ) else {
            return nil
        }
        switch text {
        case "Needs Accessibility", "Suspended":
            return .warning
        case "Error":
            return .danger
        default:
            return .neutral
        }
    }

    private static func runtimeStatusText(for state: WindowControlCoordinator.State) -> String {
        switch state {
        case .active:
            return "Active"
        case .needsAccessibility:
            return "Needs Accessibility"
        case .suspended:
            return "Suspended"
        case .error:
            return "Error"
        case .off:
            return "Off"
        }
    }

    private static func runtimeStatusKind(for state: WindowControlCoordinator.State) -> StatusPill.Kind {
        switch state {
        case .active:
            return .success
        case .needsAccessibility:
            return .warning
        case .suspended:
            return .progress
        case .error:
            return .danger
        case .off:
            return .neutral
        }
    }

    static func editRoute(for action: HotkeyAction) -> MainAppDestination {
        .windowLayouts
    }
}
