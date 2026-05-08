import Core
import SwiftUI

struct SettingsRoot: View {
    private enum SettingsTab: String, Hashable {
        case general
        case clipboard
        case downloads
        case folderPreview
        case sync
        case hotkeys
        case shortcuts
        case privacy
        case storage
        case search
        case appearance
        case advanced
    }

    let controller: AppController
    @State private var shortcuts = ShortcutRegistry.shared
    @AppStorage("settings.selectedTab", store: AppGroupSettings.defaults)
    private var selectedTabRaw = SettingsTab.general.rawValue

    var body: some View {
        TabView(selection: selectedTabBinding) {
            GeneralSettingsView(controller: controller)
                .tag(SettingsTab.general)
                .tabItem { Label("General", systemImage: "gearshape") }
            ClipboardSettingsView(controller: controller)
                .tag(SettingsTab.clipboard)
                .tabItem { Label("Clipboard", systemImage: "doc.on.clipboard") }
            DownloadsSettingsView(controller: controller)
                .tag(SettingsTab.downloads)
                .tabItem { Label("Downloads", systemImage: "arrow.down.circle") }
            FolderPreviewSettingsView(controller: controller)
                .tag(SettingsTab.folderPreview)
                .tabItem { Label("FolderPreview", systemImage: "folder") }
            SyncSettingsView(controller: controller)
                .tag(SettingsTab.sync)
                .tabItem { Label("Sync", systemImage: "icloud") }
            HotkeysSettingsView(controller: controller)
                .tag(SettingsTab.hotkeys)
                .tabItem { Label("Hotkeys", systemImage: "keyboard") }
            ShortcutsSettingsView(registry: shortcuts)
                .tag(SettingsTab.shortcuts)
                .tabItem { Label("Shortcuts", systemImage: "command.square") }
            PrivacySettingsView()
                .tag(SettingsTab.privacy)
                .tabItem { Label("Privacy", systemImage: "hand.raised") }
            StorageSettingsView()
                .tag(SettingsTab.storage)
                .tabItem { Label("Storage", systemImage: "internaldrive") }
            SearchSettingsView()
                .tag(SettingsTab.search)
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
            AppearanceSettingsView(controller: controller)
                .tag(SettingsTab.appearance)
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
            AdvancedSettingsView(controller: controller)
                .tag(SettingsTab.advanced)
                .tabItem { Label("Advanced", systemImage: "wrench") }
        }
        .frame(width: 600, height: 480)
    }

    private var selectedTabBinding: Binding<SettingsTab> {
        Binding {
            SettingsTab(rawValue: selectedTabRaw) ?? .general
        } set: { tab in
            selectedTabRaw = tab.rawValue
        }
    }
}
