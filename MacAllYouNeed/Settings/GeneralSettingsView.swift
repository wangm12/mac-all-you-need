import AppKit
import Core
import SwiftUI

enum AppAppearanceMode: String, CaseIterable, Identifiable, SegmentedTabDestination {
    case system
    case light
    case dark

    static let storageKey = "appearance.mode"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var symbolName: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }

    var appearanceName: NSAppearance.Name? {
        switch self {
        case .system: nil
        case .light: .aqua
        case .dark: .darkAqua
        }
    }

    static func storedSelection(_ raw: String?) -> AppAppearanceMode {
        raw.flatMap(AppAppearanceMode.init(rawValue:)) ?? .system
    }

    @MainActor
    static func applyStoredPreference(defaults: UserDefaults = AppGroupSettings.defaults) {
        storedSelection(defaults.string(forKey: storageKey)).apply()
    }

    @MainActor
    func apply() {
        NSApp.appearance = appearanceName.flatMap(NSAppearance.init(named:))
    }
}

enum AppChromeVisibilityControl {
    case checkbox
}

enum AppChromeVisibilityPresentation {
    static let dockIconControl: AppChromeVisibilityControl = .checkbox
    static let menuBarIconControl: AppChromeVisibilityControl = .checkbox
    static let dockIconUsesStatusPill = false
    static let menuBarIconUsesStatusPill = false
}

enum AppChromeVisibilitySettings {
    static let dockIconVisibleKey = "appearance.dockIconVisible"
    static let menuBarIconVisibleKey = "appearance.menuBarIconVisible"
    static let defaultDockIconVisible = true
    static let defaultMenuBarIconVisible = true

    static func dockIconVisible(defaults: UserDefaults = AppGroupSettings.defaults) -> Bool {
        defaults.object(forKey: dockIconVisibleKey) as? Bool ?? defaultDockIconVisible
    }

    static func menuBarIconVisible(defaults: UserDefaults = AppGroupSettings.defaults) -> Bool {
        defaults.object(forKey: menuBarIconVisibleKey) as? Bool ?? defaultMenuBarIconVisible
    }

    static func ensureVisibleEntrypoint(defaults: UserDefaults = AppGroupSettings.defaults) {
        guard !dockIconVisible(defaults: defaults), !menuBarIconVisible(defaults: defaults) else { return }
        defaults.set(defaultDockIconVisible, forKey: dockIconVisibleKey)
    }

    @MainActor
    static func applyStoredDockIconVisibility(defaults: UserDefaults = AppGroupSettings.defaults) {
        ensureVisibleEntrypoint(defaults: defaults)
        setDockIconVisible(dockIconVisible(defaults: defaults))
    }

    @MainActor
    static func setDockIconVisible(_ visible: Bool) {
        NSApp.setActivationPolicy(visible ? .regular : .accessory)
    }
}

struct GeneralSettingsView: View {
    let controller: AppController
    @AppStorage("launchAtLogin", store: AppGroupSettings.defaults) private var launchAtLogin = true
    @AppStorage("hudDurationMs", store: AppGroupSettings.defaults) private var hudDurationMs = 2000
    @AppStorage(AppAppearanceMode.storageKey, store: AppGroupSettings.defaults) private var appearanceModeRaw = AppAppearanceMode.system.rawValue
    @AppStorage(AppChromeVisibilitySettings.dockIconVisibleKey, store: AppGroupSettings.defaults) private var showDockIcon = AppChromeVisibilitySettings.defaultDockIconVisible
    @AppStorage(AppChromeVisibilitySettings.menuBarIconVisibleKey, store: AppGroupSettings.defaults) private var showMenuBarIcon = AppChromeVisibilitySettings.defaultMenuBarIconVisible

    private var appearanceMode: Binding<AppAppearanceMode> {
        Binding {
            AppAppearanceMode.storedSelection(appearanceModeRaw)
        } set: { mode in
            appearanceModeRaw = mode.rawValue
            mode.apply()
        }
    }

    var body: some View {
        MAYNSettingsPage(
            title: "General",
            subtitle: "Control how Mac All You Need launches, appears, and reports quick feedback."
        ) {
            MAYNSection(title: "App behavior") {
                MAYNSettingsRow(
                    title: "Appearance",
                    subtitle: "Follow macOS or force this app to light or dark mode."
                ) {
                    FunctionSegmentedTabStrip(
                        tabs: Array(AppAppearanceMode.allCases),
                        selection: appearanceMode.wrappedValue,
                        fillsAvailableWidth: false,
                        size: .control
                    ) { mode in
                        appearanceMode.wrappedValue = mode
                    }
                }
                MAYNDivider()
                MAYNSettingsRow(
                    title: "Launch at login",
                    subtitle: "Start the helper app automatically when macOS signs in."
                ) {
                    Toggle("", isOn: $launchAtLogin)
                        .labelsHidden()
                }
                MAYNDivider()
                MAYNSettingsRow(
                    title: "Dock icon",
                    subtitle: "Show Mac All You Need in the Dock."
                ) {
                    Toggle("", isOn: $showDockIcon)
                        .toggleStyle(.checkbox)
                        .labelsHidden()
                        .disabled(!showMenuBarIcon)
                }
            }

            MAYNSection(title: "Menu bar and feedback") {
                MAYNSettingsRow(
                    title: "Menu bar icon",
                    subtitle: "Show the quick command center in the macOS menu bar."
                ) {
                    Toggle("", isOn: $showMenuBarIcon)
                        .toggleStyle(.checkbox)
                        .labelsHidden()
                        .disabled(!showDockIcon)
                }
                MAYNDivider()
                MAYNSettingsRow(
                    title: "Notification duration",
                    subtitle: "How long copy, download, and voice status chips stay visible."
                ) {
                    MAYNDropdown(
                        selection: $hudDurationMs,
                        options: [1000, 2000, 3000, 5000],
                        title: hudDurationTitle
                    )
                }
            }
        }
        .onChange(of: launchAtLogin) { _, on in
            LoginItemController.setLaunchAtLogin(on)
        }
        .onChange(of: showDockIcon) { _, visible in
            if !visible, !showMenuBarIcon {
                showMenuBarIcon = true
            }
            AppChromeVisibilitySettings.setDockIconVisible(visible)
        }
        .onChange(of: showMenuBarIcon) { _, visible in
            if !visible, !showDockIcon {
                showDockIcon = true
            }
        }
        .onAppear {
            AppAppearanceMode.storedSelection(appearanceModeRaw).apply()
            AppChromeVisibilitySettings.applyStoredDockIconVisibility()
        }
    }

    private func hudDurationTitle(_ milliseconds: Int) -> String {
        switch milliseconds {
        case 1000:
            "1 second"
        default:
            "\(milliseconds / 1000) seconds"
        }
    }
}
