import SwiftUI

struct SettingsRoot: View {
    let controller: AppController
    @State private var shortcuts = ShortcutRegistry.shared

    var body: some View {
        TabView {
            GeneralSettingsView(controller: controller)
                .tabItem { Label("General", systemImage: "gearshape") }
            ClipboardSettingsView(controller: controller)
                .tabItem { Label("Clipboard", systemImage: "doc.on.clipboard") }
            DownloadsSettingsView(controller: controller)
                .tabItem { Label("Downloads", systemImage: "arrow.down.circle") }
            FolderPreviewSettingsView(controller: controller)
                .tabItem { Label("FolderPreview", systemImage: "folder") }
            SyncSettingsView(controller: controller)
                .tabItem { Label("Sync", systemImage: "icloud") }
            HotkeysSettingsView(controller: controller)
                .tabItem { Label("Hotkeys", systemImage: "keyboard") }
            ShortcutsSettingsView(registry: shortcuts)
                .tabItem { Label("Shortcuts", systemImage: "command.square") }
            AdvancedSettingsView(controller: controller)
                .tabItem { Label("Advanced", systemImage: "wrench") }
        }
        .frame(width: 600, height: 480)
    }
}
