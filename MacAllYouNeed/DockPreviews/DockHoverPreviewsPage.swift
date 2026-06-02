import ApplicationServices
import Core
import SwiftUI

struct DockHoverPreviewsPage: View {
    let controller: AppController
    @AppStorage(DockFunctionTab.storageKey, store: AppGroupSettings.defaults) private var tabRaw = DockFunctionTab.features.rawValue

    private var selectedTab: Binding<DockFunctionTab> {
        Binding {
            DockFunctionTab.storedSelection(tabRaw)
        } set: { tabRaw = $0.rawValue }
    }

    var body: some View {
        FunctionPageShell(
            title: "Dock",
            subtitle: "Hover previews, window switcher, Cmd+Tab, dock lock, and active-app indicator.",
            selection: selectedTab
        ) {
            DockSettingsPageBody(tab: selectedTab.wrappedValue) {
                controller.dockPreviewsReloadSettings()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            controller.dockPreviewsRefreshPermissions()
        }
    }
}
