import ApplicationServices
import Core
import FeatureCore
import Platform
import SwiftUI

struct WindowHubSettingsView: View {
    var controller: AppController?
    @Binding var settings: WindowHubSettings
    @Binding var hotkeyMap: [HotkeyAction: [Platform.HotkeyDescriptor]]
    var onChange: () -> Void = {}
    @State private var axTrusted = AXIsProcessTrusted()

    init(
        controller: AppController? = nil,
        settings: Binding<WindowHubSettings> = .constant(WindowHubSettingsStore.load()),
        hotkeyMap: Binding<[HotkeyAction: [Platform.HotkeyDescriptor]]> = .constant(HotkeyMapStore.defaultMap),
        onChange: @escaping () -> Void = {}
    ) {
        self.controller = controller
        _settings = settings
        _hotkeyMap = hotkeyMap
        self.onChange = onChange
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            overviewSection
            permissionsSection
            shortcutSection
            panelSection
            aiOrganizeSection
            relatedToolsSection
        }
        .onAppear {
            refreshAccessibilityTrust()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshAccessibilityTrust()
        }
        .onChange(of: settings.browserTabDiscoveryEnabled) { _, enabled in
            if enabled {
                BrowserAppleScriptTabCache.resetAccessState()
            }
        }
        .onChange(of: settings) { _, newValue in
            WindowHubSettingsStore.save(newValue)
            onChange()
        }
    }

    // MARK: - Sections

    private var overviewSection: some View {
        MAYNSection(
            title: "Window Hub",
            subtitle: "Text-only window and tab switching — no screenshots or background capture."
        ) {
            MAYNSettingsRow(
                title: "Open panel",
                subtitle: "Use your shortcut anywhere, or open the hub from here."
            ) {
                MAYNButton("Open Window Hub", role: .primary) {
                    controller?.windowHubTogglePanel()
                }
                .disabled(controller == nil)
            }
            MAYNDivider()
            MAYNSettingsRow(
                title: "Inside the panel",
                subtitle: "Search apps, windows, and tabs; use AI Organize to review and apply batch changes."
            ) {
                EmptyView()
            }
        }
    }

    private var permissionsSection: some View {
        MAYNSection(
            title: "Permissions",
            subtitle: "Accessibility is required to list windows and switch focus."
        ) {
            AccessibilityPermissionRow(
                status: PermissionStatusProvider.requiredPermission(isGranted: axTrusted),
                isHighlighted: !axTrusted,
                onAction: openAccessibilitySettings
            )
        }
    }

    private var shortcutSection: some View {
        MAYNSection(
            title: "Shortcut",
            subtitle: "Global shortcut for the floating panel."
        ) {
            MAYNSettingsRow(
                title: "Open Window Hub",
                subtitle: "Default is Option+Shift+W."
            ) {
                HotkeyRecorderControl(
                    descriptor: hotkeyBinding,
                    issueMessage: windowHubHotkeyIssueMessage,
                    candidateIssueMessage: windowHubHotkeyCandidateIssueMessage,
                    defaultDescriptor: HotkeyAction.windowHub.primaryDefaultDescriptor,
                    recorderWidth: 112,
                    errorWidth: 260,
                    reset: resetHotkey
                )
            }
        }
    }

    private var panelSection: some View {
        MAYNSection(
            title: "Panel",
            subtitle: "Controls what appears in the compact masonry dashboard."
        ) {
            MAYNSettingsRow(
                title: "Show background apps",
                subtitle: "Include running apps with no visible windows in the dashboard."
            ) {
                Toggle("", isOn: $settings.showBackgroundApps)
                    .labelsHidden()
                    .maynSwitchToggleStyle()
            }
            MAYNDivider()
            MAYNSettingsRow(
                title: "Browser tab discovery",
                subtitle: browserTabDiscoverySubtitle
            ) {
                Toggle("", isOn: $settings.browserTabDiscoveryEnabled)
                    .labelsHidden()
                    .maynSwitchToggleStyle()
            }
            if settings.browserTabDiscoveryEnabled, browserAutomationDenied {
                MAYNSettingsRow(
                    title: "Automation access",
                    subtitle: "Enable Mac All You Need for each browser under System Settings → Privacy & Security → Automation."
                ) {
                    MAYNButton("Open Settings", role: .secondary) {
                        openAutomationSettings()
                    }
                }
            }
            MAYNDivider()
            MAYNSettingsRow(
                title: "Tabs shown per window",
                subtitle: "Each window shows this many tabs before collapsing into a \"Show all\" row."
            ) {
                MAYNDropdown(
                    selection: $settings.tabsPerWindow,
                    options: Self.tabsPerWindowOptions,
                    title: { $0 >= 50 ? "50 (max)" : "\($0)" }
                )
            }
        }
    }

    private static let tabsPerWindowOptions = [5, 10, 15, 20, 30, 50]

    private var browserTabDiscoverySubtitle: String {
        "On by default. Reads Chromium tabs through Automation; macOS may ask once per browser to access app data."
    }

    private var browserAutomationDenied: Bool {
        BrowserAppleScriptTabCache.isAccessDenied(for: "com.google.Chrome")
            || BrowserAppleScriptTabCache.isAccessDenied(for: "com.google.Chrome.canary")
    }

    private var aiOrganizeSection: some View {
        MAYNSection(
            title: "AI Organize",
            subtitle: "AI suggestions always open in a review sheet. Nothing runs until you select items and tap Apply."
        ) {
            MAYNSettingsRow(
                title: "Skip confirmation for low-risk closes",
                subtitle: "Pinned, audible, private, and quit actions still require confirmation."
            ) {
                Toggle("", isOn: $settings.skipLowRiskConfirmations)
                    .labelsHidden()
                    .maynSwitchToggleStyle()
            }
            MAYNDivider()
            MAYNSettingsRow(
                title: "Send full URLs to AI",
                subtitle: "Off by default. AI Organize only receives tab titles and domains unless you opt in."
            ) {
                Toggle("", isOn: $settings.aiSendFullURLs)
                    .labelsHidden()
                    .maynSwitchToggleStyle()
            }
        }
    }

    private var relatedToolsSection: some View {
        MAYNSection(
            title: "Related tools",
            subtitle: "Other window features that share Accessibility permission."
        ) {
            relatedToolRow(
                title: "Window Layouts",
                subtitle: "Snap, arrange, maximize, and restore windows with keyboard shortcuts.",
                symbol: "rectangle.3.group",
                destination: .windowLayouts
            )
            MAYNDivider()
            relatedToolRow(
                title: "Window Grab",
                subtitle: "Hold a modifier and drag windows from any visible area.",
                symbol: "hand.draw",
                destination: .grabAnywhere
            )
            MAYNDivider()
            relatedToolRow(
                title: "Permissions",
                subtitle: "Review Accessibility and other Mac All You Need permissions.",
                symbol: "lock.shield",
                destination: .settings,
                settingsTab: .permissions
            )
        }
    }

    // MARK: - Related tool rows

    @ViewBuilder
    private func relatedToolRow(
        title: String,
        subtitle: String,
        symbol: String,
        destination: MainAppDestination,
        settingsTab: SettingsDestination? = nil
    ) -> some View {
        MAYNSettingsRow(title: title, subtitle: subtitle) {
            if let controller {
                MAYNButton("Open", role: .secondary) {
                    if let settingsTab {
                        AppGroupSettings.defaults.set(
                            settingsTab.rawValue,
                            forKey: DockSettingsNavigation.settingsSelectionKey
                        )
                    }
                    controller.showMainWindow(destination: destination)
                }
            } else {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Hotkey

    private var hotkeyBinding: Binding<Platform.HotkeyDescriptor> {
        Binding {
            let defaultDescriptor = HotkeyAction.windowHub.primaryDefaultDescriptor ?? .defaultWindowHub
            let descriptors = hotkeyMap[.windowHub] ?? [defaultDescriptor]
            return descriptors.first ?? defaultDescriptor
        } set: { newValue in
            saveHotkey(newValue)
        }
    }

    private var windowHubHotkeyIssueMessage: String? {
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

    private func windowHubHotkeyCandidateIssueMessage(_ descriptor: Platform.HotkeyDescriptor) -> String? {
        HotkeyValidation.issue(
            forAppHotkey: descriptor,
            action: .windowHub,
            index: 0,
            appHotkeys: hotkeyMap,
            voiceShortcut: VoiceActivationSettingsStore.load().shortcut,
            dockShortcuts: HotkeyValidation.liveDockShortcuts()
        )?.message
    }

    private func saveHotkey(_ descriptor: Platform.HotkeyDescriptor) {
        var next = hotkeyMap
        next[.windowHub] = [descriptor]
        guard HotkeyValidation.firstIssue(
            in: next,
            voiceShortcut: VoiceActivationSettingsStore.load().shortcut,
            dockShortcuts: HotkeyValidation.liveDockShortcuts()
        ) == nil else {
            hotkeyMap = next
            return
        }
        hotkeyMap = next
        HotkeyMapStore.save(next)
        NotificationCenter.default.post(name: .windowHubHotkeyDidChange, object: nil)
        onChange()
    }

    private func resetHotkey() {
        let defaultDescriptor = HotkeyAction.windowHub.primaryDefaultDescriptor ?? .defaultWindowHub
        saveHotkey(defaultDescriptor)
    }

    private func refreshAccessibilityTrust() {
        axTrusted = AXIsProcessTrusted()
    }

    private func openAccessibilitySettings() {
        NSWorkspace.shared.open(
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        )
    }

    private func openAutomationSettings() {
        NSWorkspace.shared.open(
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!
        )
    }
}
