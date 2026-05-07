import AppKit
import Core
import SwiftUI

struct AppMenuBarContent: View {
    let controller: AppController
    @State private var tab: Tab = .clipboard

    enum Tab: Hashable { case clipboard, downloads, snippets }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Mac All You Need").font(.system(size: 13, weight: .semibold))
                Spacer()
                SyncStatusChip()
                SettingsLink { Image(systemName: "gear") }
                    .buttonStyle(.borderless)
            }
            .padding(.horizontal, 10).padding(.top, 8)

            Picker("", selection: $tab) {
                Text("Clipboard").tag(Tab.clipboard)
                Text("Downloads").tag(Tab.downloads)
                Text("Snippets").tag(Tab.snippets)
            }.pickerStyle(.segmented).padding(8)
            Divider()

            Group {
                switch tab {
                case .clipboard:
                    ClipboardMenuBarContent(deps: controller.clipboardDeps)
                case .downloads:
                    DownloadsListView(vm: controller.downloaderVM)
                case .snippets:
                    SnippetsListView(xpc: controller.clipboardDeps.xpc)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            HStack {
                Text("⌘⇧V").font(.system(.caption, design: .monospaced))
                Text("clipboard popup").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }.buttonStyle(.borderless).font(.caption)
            }.padding(.horizontal, 10).padding(.vertical, 6)
        }
        .frame(width: 480, height: 580)
    }
}

struct SyncStatusChip: View {
    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(Color.gray).frame(width: 6, height: 6)
            Text("Local only").font(.caption2).foregroundStyle(.secondary)
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
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task { await deps.refresh() }
    }
}

struct SnippetsListView: View {
    let xpc: ClipboardXPCClient
    @State private var snippets: [SnippetXPCDTO] = []
    var body: some View {
        List(snippets) { snippet in
            VStack(alignment: .leading, spacing: 2) {
                Text(snippet.name)
                if let trigger = snippet.trigger {
                    Text(trigger).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .overlay {
            if snippets.isEmpty {
                Text("No snippets yet").foregroundStyle(.secondary)
            }
        }
        .task { await refresh() }
    }

    private func refresh() async {
        snippets = await withCheckedContinuation { cont in
            // Use an error handler so the continuation is always resumed,
            // even if the XPC connection drops before the callback fires.
            let proxy = xpc.connection.remoteObjectProxyWithErrorHandler { _ in
                cont.resume(returning: [])
            } as? ClipboardXPCProtocol
            guard let proxy else { cont.resume(returning: []); return }
            proxy.listSnippets { cont.resume(returning: $0) }
        }
    }
}
