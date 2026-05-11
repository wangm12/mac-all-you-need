import AppKit
import Core
import Platform
import SwiftUI

struct AppMenuBarContent: View {
    let controller: AppController
    @State private var tab: Tab = .clipboard
    @Environment(\.openSettings) private var openSettings

    enum Tab: Hashable { case clipboard, downloads, snippets }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Mac All You Need").font(.system(size: 13, weight: .semibold))
                Spacer()
                SyncStatusChip()
                Button {
                    NSApp.activate(ignoringOtherApps: true)
                    openSettings()
                } label: { Image(systemName: "gear") }
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
                    ClipboardMenuBarContent(
                        reader: controller.clipboardReader,
                        imageLoader: controller.clipboardDeps.imageLoader,
                        blobs: controller.clipboardDeps.blobs
                    )
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
                Text("clipboard dock").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Pause 60s") {
                    controller.suspendCaptureFor60Seconds()
                }
                .buttonStyle(.borderless)
                .font(.caption)
                Button("Quit") { NSApp.terminate(nil) }.buttonStyle(.borderless).font(.caption)
            }.padding(.horizontal, 10).padding(.vertical, 6)
        }
        .frame(width: 480, height: 580)
        .onAppear {
            // Opening the menu-bar popover dismisses the dock — having both
            // visible at once is messy and the user clicked the menu icon
            // explicitly, signalling they want this surface instead.
            controller.clipboardDock.hide()
            // Also dismiss any floating preview/HUD so the popover appears
            // on a clean canvas.
            PreviewPanel.dismiss()
        }
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
    let reader: LocalClipboardReader
    let imageLoader: ImageBlobLoader
    let blobs: BlobStore

    /// Currently-highlighted row. Click only sets this — copying requires
    /// an explicit ⌘C (matches the dock's Finder-style click semantics).
    @State private var selectedID: String?
    @FocusState private var listFocused: Bool

    var body: some View {
        Group {
            if reader.items.isEmpty {
                Text("No items yet")
                    .foregroundStyle(.tertiary).font(.callout)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(reader.items, id: \.id.rawValue) { item in
                                ClipboardItemRow2(
                                    item: item,
                                    imageLoader: imageLoader,
                                    isSelected: selectedID == item.id.rawValue,
                                    onSelect: { selectedID = item.id.rawValue },
                                    onActivate: {
                                        // Double-click = "I want this one":
                                        // make sure it's the selection,
                                        // then copy + dismiss the popover.
                                        selectedID = item.id.rawValue
                                        copySelectedAndDismiss()
                                    }
                                )
                                .id(item.id.rawValue)
                                Divider().opacity(0.4)
                            }
                        }
                    }
                    .onChange(of: selectedID) { _, newID in
                        guard let newID else { return }
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo(newID, anchor: .center)
                        }
                        // If the preview window is open, swap to the newly
                        // selected item so the user can scrub through
                        // images by holding ↑/↓ while previewing.
                        if PreviewPanel.isVisible {
                            previewSelected()
                        }
                    }
                }
            }
        }
        .focusable()
        .focusEffectDisabled()
        .focused($listFocused)
        .onAppear {
            listFocused = true
            // Default to the most recent item so ⌘C works immediately
            // without needing a prior click.
            if selectedID == nil {
                selectedID = reader.items.first?.id.rawValue
            }
        }
        .onChange(of: reader.items.map(\.id.rawValue)) { _, ids in
            // Keep selection valid across reader reloads — fall back to the
            // newest item when the previously-selected one was deleted.
            if let selectedID, !ids.contains(selectedID) {
                self.selectedID = ids.first
            } else if selectedID == nil {
                selectedID = ids.first
            }
        }
        .onKeyPress(keys: ["c"]) { keyPress in
            guard keyPress.modifiers.contains(.command) else { return .ignored }
            copySelectedAndDismiss()
            return .handled
        }
        .onKeyPress(.space) {
            previewSelected()
            return .handled
        }
        .onKeyPress(.downArrow) { moveSelection(by: 1); return .handled }
        .onKeyPress(.upArrow) { moveSelection(by: -1); return .handled }
        .onKeyPress(.return) { copySelectedAndDismiss(); return .handled }
    }

    private func moveSelection(by delta: Int) {
        let ids = reader.items.map(\.id.rawValue)
        guard !ids.isEmpty else { return }
        let currentIdx = selectedID.flatMap { ids.firstIndex(of: $0) } ?? 0
        let nextIdx = max(0, min(ids.count - 1, currentIdx + delta))
        // Boundary no-op: at the start (delta=-1) or end (delta=+1) of the
        // list, don't re-set selectedID — that would re-fire onChange and
        // (if preview is open) cause a perceptible flash.
        guard nextIdx != currentIdx else { return }
        selectedID = ids[nextIdx]
    }

    /// ⌘C path: write the selected item to NSPasteboard with the daemon-
    /// write sentinel (so the daemon doesn't re-capture it as a duplicate),
    /// dismiss the popover, and float the "Copied" HUD.
    private func copySelectedAndDismiss() {
        guard let selectedID,
              let item = reader.items.first(where: { $0.id.rawValue == selectedID }),
              let store = reader.store,
              let body = try? store.body(for: item.id)
        else { return }
        ClipboardXPCService.restoreToPasteboard(body: body, blobs: blobs, pasteboard: .general)
        NSPasteboard.general.setData(Data([0]), forType: PasteboardUTI.daemonWrite)
        Self.dismissMenuBarPopover()
        CopyHUD.show("Copied")
    }

    /// Programmatically close the MenuBarExtra `.window`-style popover.
    /// `NSApp.deactivate()` alone is unreliable here because the popover
    /// panel is non-activating — deactivating the app is a no-op for it.
    /// We walk `NSApp.windows` looking for the MenuBarExtra panel (its
    /// class name contains "MenuBarExtra") and order it out, which is the
    /// same effect as clicking the status item again.
    static func dismissMenuBarPopover() {
        for window in NSApp.windows {
            let name = String(describing: type(of: window))
            if name.contains("MenuBarExtra") || name.contains("NSStatusBarWindow") {
                window.orderOut(nil)
            }
        }
        // Belt-and-suspenders: also deactivate the app so any other
        // attached popovers tear down via the standard path.
        NSApp.deactivate()
    }

    /// Space path: open the floating preview panel for the currently-
    /// selected item. Images render inline; text/code/html/rtf render as
    /// scrollable, selectable text. Other kinds (color/link/multi-file)
    /// fall through silently.
    private func previewSelected() {
        guard let selectedID,
              let item = reader.items.first(where: { $0.id.rawValue == selectedID }),
              let store = reader.store,
              let body = try? store.body(for: item.id)
        else { return }
        switch body {
        case let .image(blobID, _, _):
            if let data = try? blobs.read(id: blobID),
               let image = NSImage(data: data)
            {
                PreviewPanel.show(.image(image))
            }
        case let .files(urls) where urls.count == 1 && Self.isImageURL(urls[0]):
            if let image = NSImage(contentsOf: urls[0]) {
                PreviewPanel.show(.image(image))
            }
        case let .text(s):
            PreviewPanel.show(.text(s, monospaced: false))
        case let .html(s):
            // Strip tags for the preview pane (full HTML rendering would
            // need a WKWebView and isn't worth the complexity here).
            let plain = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            PreviewPanel.show(.text(plain, monospaced: false))
        case let .rtf(data):
            if let attr = NSAttributedString(rtf: data, documentAttributes: nil) {
                PreviewPanel.show(.text(attr.string, monospaced: false))
            }
        case .files:
            // Multi-file or non-image file — no inline preview.
            break
        }
    }

    private static func isImageURL(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ["png", "jpg", "jpeg", "gif", "heic", "heif", "webp", "tiff", "tif", "bmp"].contains(ext)
    }
}

private struct ClipboardItemRow2: View {
    let item: ClipboardItemMeta
    let imageLoader: ImageBlobLoader
    let isSelected: Bool
    let onSelect: () -> Void
    let onActivate: () -> Void

    @State private var isHovering = false

    private var isImage: Bool { item.preview.hasPrefix("(image ") }

    private var icon: String {
        if isImage { return "photo" }
        if item.preview.hasPrefix("(") && item.preview.contains("file") { return "doc" }
        if item.preview.hasPrefix("http") { return "link" }
        return "doc.plaintext"
    }

    private var displayText: String {
        item.customLabel ?? item.preview.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        HStack(spacing: 10) {
            // Image-kind rows show an actual thumbnail; everything else
            // falls back to a kind-appropriate SF Symbol.
            Group {
                if isImage {
                    MenuBarImageThumbnail(
                        recordID: item.id.rawValue,
                        loader: imageLoader
                    )
                } else {
                    Image(systemName: icon)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                }
            }

            Text(displayText)
                .lineLimit(2)
                .font(.callout)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            Text(CompactTimestamp.format(item.modified))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(rowBackground)
        .overlay(alignment: .leading) {
            // 3pt accent stripe on the leading edge of the selected row —
            // mirrors the dock's accent border, but list-row friendlier.
            Rectangle()
                .fill(isSelected ? Color.accentColor : .clear)
                .frame(width: 3)
        }
        .onHover { isHovering = $0 }
        .onTapGesture { onSelect() }
        // Double-click = activate (copy + dismiss popover). Same
        // simultaneousGesture trick as the dock carousel so the
        // single-tap doesn't wait on double-tap disambiguation.
        .simultaneousGesture(
            TapGesture(count: 2).onEnded { onActivate() }
        )
    }

    private var rowBackground: Color {
        if isSelected { return Color.accentColor.opacity(0.18) }
        if isHovering { return Color.secondary.opacity(0.10) }
        return .clear
    }
}

/// 36×36 thumbnail rendered from the `ImageBlobLoader`. Falls back to a
/// placeholder SF Symbol while loading or if the blob can't be decoded.
private struct MenuBarImageThumbnail: View {
    let recordID: String
    let loader: ImageBlobLoader
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "photo")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 36, height: 36)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)
        )
        .task(id: recordID) {
            image = await loader.thumbnail(recordID: recordID, maxDim: 80)
        }
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
