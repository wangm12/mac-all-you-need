import AppKit
import Core
import SwiftUI

struct DockMoreMenu: View {
    /// Called before opening Settings so the dock can hide itself — the dock
    /// window sits at `.popUpMenu` level which would otherwise cover the
    /// Settings window and make it look like nothing happened.
    let dismissDock: () -> Void
    @State private var confirmingClearEverything = false

    var body: some View {
        Menu {
            // Flat structure — submenus inside a SwiftUI Menu hosted in a
            // borderless nonactivating NSPanel are unreliable; clicks on
            // nested items frequently never reach the action closure.
            Button("Open Clipboard Rules…") {
                DockSettingsNavigation.requestClipboardRules(dismissDock: dismissDock)
            }
            Button("Pause Capture for 60s") {
                NotificationCenter.default.post(name: .pauseCaptureRequested, object: nil)
            }

            Divider()

            Button("Clear Older Than 1 Day") {
                NotificationCenter.default.post(name: .clearClipboardOlderThanRequested, object: 1)
            }
            Button("Clear Older Than 7 Days") {
                NotificationCenter.default.post(name: .clearClipboardOlderThanRequested, object: 7)
            }
            Button("Clear Older Than 30 Days") {
                NotificationCenter.default.post(name: .clearClipboardOlderThanRequested, object: 30)
            }
            Button("Clear Everything", role: .destructive) {
                confirmingClearEverything = true
            }

            Divider()

            Button("Open Settings…") {
                openSettingsAndDismiss(.general)
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        // Drop the trailing ▾ chevron — the ellipsis itself is a clear
        // affordance, the chevron is visual noise.
        .menuIndicator(.hidden)
        .frame(width: 28, height: 28)
        .confirmationDialog(
            DockMoreMenuClearEverythingConfirmation.title,
            isPresented: $confirmingClearEverything
        ) {
            Button(DockMoreMenuClearEverythingConfirmation.actionTitle, role: .destructive) {
                NotificationCenter.default.post(name: .clearAllClipboardHistoryRequested, object: nil)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(DockMoreMenuClearEverythingConfirmation.message)
        }
    }

    private func openSettingsAndDismiss(_ destination: SettingsDestination) {
        DockSettingsNavigation.request(destination, dismissDock: dismissDock)
    }
}

enum DockMoreMenuClearEverythingConfirmation {
    static let title = "Clear all clipboard history?"
    static let message = "This permanently removes every clipboard history item, including pinned cards. Snippets and lists stay."
    static let actionTitle = "Clear Everything"
}

enum DockSettingsNavigation {
    static let settingsSelectionKey = "settings.selectedTab"
    static let clipboardRulesRoute = "clipboard.rules"

    static func request(
        _ destination: SettingsDestination,
        defaults: UserDefaults = AppGroupSettings.defaults,
        notificationCenter: NotificationCenter = .default,
        dismissDock: () -> Void,
        activateApp: () -> Void = { NSApp.activate(ignoringOtherApps: true) }
    ) {
        defaults.set(destination.rawValue, forKey: settingsSelectionKey)
        dismissDock()
        activateApp()
        notificationCenter.post(name: .mainWindowSettingsRequested, object: destination.rawValue)
    }

    static func requestClipboardRules(
        defaults: UserDefaults = AppGroupSettings.defaults,
        notificationCenter: NotificationCenter = .default,
        dismissDock: () -> Void,
        activateApp: () -> Void = { NSApp.activate(ignoringOtherApps: true) }
    ) {
        defaults.set(ClipboardFunctionTab.rules.rawValue, forKey: ClipboardFunctionTab.storageKey)
        dismissDock()
        activateApp()
        notificationCenter.post(name: .mainWindowSettingsRequested, object: clipboardRulesRoute)
    }

    static func isClipboardRulesRoute(_ raw: String?) -> Bool {
        raw == clipboardRulesRoute || raw == "privacy"
    }
}

extension Notification.Name {
    static let mainWindowSettingsRequested = Notification.Name("mainWindowSettingsRequested")
    static let globalSettingsOpenRequested = Notification.Name("globalSettingsOpenRequested")
}
