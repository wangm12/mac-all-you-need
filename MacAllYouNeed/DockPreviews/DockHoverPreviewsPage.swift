import Core
import SwiftUI

struct DockHoverPreviewsPage: View {
    let controller: AppController
    @AppStorage(DockPreviewFunctionTab.storageKey, store: AppGroupSettings.defaults) private var tabRaw = DockPreviewFunctionTab.overview.rawValue

    private var selectedTab: Binding<DockPreviewFunctionTab> {
        Binding {
            DockPreviewFunctionTab.storedSelection(tabRaw)
        } set: { tabRaw = $0.rawValue }
    }

    var body: some View {
        FunctionPageShell(
            title: "Dock",
            subtitle: "Hover previews, window switcher, Cmd+Tab, dock lock, and active-app indicator.",
            selection: selectedTab
        ) {
            switch DockPreviewFunctionTab.storedSelection(tabRaw) {
            case .overview:
                FunctionPageScrollContent {
                    overviewContent
                }
            case .settings:
                FunctionPageScrollContent {
                    DockSettingsTabContent(onSettingsChanged: {
                        controller.dockPreviewsReloadSettings()
                    })
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            controller.dockPreviewsRefreshPermissions()
        }
    }

    private var overviewContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            InstructionStrip(
                text: "Enable Dock from the Dashboard, then configure each capability in Settings.",
                symbol: "dock.rectangle",
                secondaryText: "Move into the preview panel to keep it open while you choose a window."
            )
            MAYNSection(title: "Permissions") {
                MAYNSettingsRow(
                    title: "Accessibility",
                    subtitle: "Required to detect which Dock icon you are hovering."
                ) {
                    StatusPill(
                        text: AXIsProcessTrusted() ? "Granted" : "Needed",
                        kind: AXIsProcessTrusted() ? .success : .warning
                    )
                }
                MAYNDivider()
                MAYNSettingsRow(
                    title: "Screen Recording",
                    subtitle: "Optional. Without it, previews show window titles only."
                ) {
                    StatusPill(
                        text: DockPreviewPermissionGate.screenRecordingGranted() ? "Granted" : "Optional",
                        kind: DockPreviewPermissionGate.screenRecordingGranted() ? .success : .neutral
                    )
                }
                MAYNDivider()
                MAYNSettingsRow(
                    title: "Open Privacy settings",
                    subtitle: "Grant Accessibility or Screen Recording if previews do not appear."
                ) {
                    MAYNButton("Open Settings", role: .secondary) {
                        NSWorkspace.shared.open(
                            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy")!
                        )
                    }
                }
            }
        }
    }
}
