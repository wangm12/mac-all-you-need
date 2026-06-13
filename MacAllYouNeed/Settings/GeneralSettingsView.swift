import AppKit
import Core
import Platform
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

/// Three-step sensitivity for modifier double-tap detection.
/// Raw values are `String` to satisfy `SegmentedTabDestination : RawRepresentable<String>`.
/// The actual timing is stored as a `Double` under `ModifierTapTiming.multiTapWindowKey`.
enum DoubleTapSpeed: String, CaseIterable, SegmentedTabDestination {
    case fast
    case normal
    case slow

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fast:   "Fast"
        case .normal: "Normal"
        case .slow:   "Slow"
        }
    }

    var symbolName: String {
        switch self {
        case .fast:   "hare"
        case .normal: "figure.walk"
        case .slow:   "tortoise"
        }
    }

    /// The double-tap window stored in `ModifierTapTiming.multiTapWindowKey`.
    /// 0.0 = use system `NSEvent.doubleClickInterval` (Normal).
    var windowValue: TimeInterval {
        switch self {
        case .fast:   0.22
        case .normal: 0.0
        case .slow:   0.45
        }
    }

    static func from(stored: TimeInterval) -> DoubleTapSpeed {
        switch stored {
        case 0.22: .fast
        case 0.45: .slow
        default:   .normal
        }
    }

    static var allCasesOrdered: [DoubleTapSpeed] { [.fast, .normal, .slow] }
}

struct GeneralSettingsView: View {
    let controller: AppController
    // swiftlint:disable line_length
    @AppStorage("launchAtLogin", store: AppGroupSettings.defaults) private var launchAtLogin = true
    @AppStorage("hudDurationMs", store: AppGroupSettings.defaults) private var hudDurationMs = 2000
    @AppStorage(AppAppearanceMode.storageKey, store: AppGroupSettings.defaults) private var appearanceModeRaw = AppAppearanceMode.system.rawValue
    @AppStorage(AppChromeVisibilitySettings.dockIconVisibleKey, store: AppGroupSettings.defaults) private var showDockIcon = AppChromeVisibilitySettings.defaultDockIconVisible
    @AppStorage(AppChromeVisibilitySettings.menuBarIconVisibleKey, store: AppGroupSettings.defaults) private var showMenuBarIcon = AppChromeVisibilitySettings.defaultMenuBarIconVisible
    @AppStorage(ModifierTapTiming.multiTapWindowKey, store: AppGroupSettings.defaults) private var multiTapWindowRaw = 0.0
    // swiftlint:enable line_length

    private var appearanceMode: Binding<AppAppearanceMode> {
        Binding {
            AppAppearanceMode.storedSelection(appearanceModeRaw)
        } set: { mode in
            appearanceModeRaw = mode.rawValue
            mode.apply()
        }
    }

    private var doubleTapSpeed: Binding<DoubleTapSpeed> {
        Binding {
            DoubleTapSpeed.from(stored: multiTapWindowRaw)
        } set: { speed in
            multiTapWindowRaw = speed.windowValue
            ModifierTapDispatcher.shared.multiTapWindow = ModifierTapTiming.multiTapWindow
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
                MAYNDivider()
                MAYNSettingsRow(
                    title: "Double tap speed",
                    subtitle: "How quickly you must double-tap a modifier key. Normal uses your system double-click speed."
                ) {
                    FunctionSegmentedTabStrip(
                        tabs: DoubleTapSpeed.allCasesOrdered,
                        selection: doubleTapSpeed.wrappedValue,
                        fillsAvailableWidth: false,
                        size: .control
                    ) { speed in
                        doubleTapSpeed.wrappedValue = speed
                    }
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
