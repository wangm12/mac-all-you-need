import Core
import SwiftUI

@main
struct MacAllYouNeedApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var deps = AppDependencies()
    @State private var popup: ClipboardPopupController?
    @State private var hotkey: HotkeyController?

    var body: some Scene {
        MenuBarExtra("Mac All You Need", systemImage: "tray.full") {
            ClipboardMenuBarContent(deps: deps)
        }
        .menuBarExtraStyle(.window)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, hotkey == nil {
                let p = ClipboardPopupController(deps: deps)
                let h = HotkeyController(popup: p)
                h.registerDefault()
                popup = p
                hotkey = h
            }
        }
    }
}

struct ClipboardMenuBarContent: View {
    let deps: AppDependencies
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Recent clipboard").font(.caption).foregroundStyle(.secondary)
            ForEach(deps.recentItems, id: \.id) { item in
                HStack {
                    Text(item.preview).lineLimit(1).truncationMode(.tail)
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if deps.recentItems.isEmpty {
                Text("No items yet").foregroundStyle(.tertiary).font(.callout)
            }
        }
        .padding(12)
        .frame(width: 480)
        .task { await deps.refresh() }
    }
}
