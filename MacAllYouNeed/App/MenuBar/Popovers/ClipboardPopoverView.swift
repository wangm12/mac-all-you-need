import AppKit
import Core
import Platform
import SwiftUI

struct ClipboardPopoverView: View {
    let reader: LocalClipboardReader
    let imageLoader: ImageBlobLoader
    let appIcons: AppIconResolver
    let blobs: BlobStore

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var listFocused: Bool
    @State private var keyMonitor: NSEventMonitorHandle? = nil

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
                                    appIcons: appIcons,
                                    isSelected: reader.selectedIDs.contains(item.id.rawValue),
                                    onTap: { handleTap(id: item.id.rawValue) },
                                    onActivate: {
                                        reader.selectedIDs = [item.id.rawValue]
                                        reader.anchorID = item.id.rawValue
                                        copySelectedAndDismiss()
                                    },
                                    onCopy: {
                                        reader.selectedIDs = [item.id.rawValue]
                                        reader.anchorID = item.id.rawValue
                                        copySelectedAndDismiss()
                                    }
                                )
                                .id(item.id.rawValue)
                                Divider().opacity(0.4)
                            }
                        }
                    }
                    .onChange(of: reader.anchorID) { _, newID in
                        guard let newID else { return }
                        if reduceMotion {
                            proxy.scrollTo(newID, anchor: .center)
                        } else {
                            withAnimation(MAYNMotion.animation(.hover, reduceMotion: reduceMotion)) {
                                proxy.scrollTo(newID, anchor: .center)
                            }
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
            if reader.anchorID == nil {
                reader.anchorID = reader.items.first?.id.rawValue
                if let a = reader.anchorID { reader.selectedIDs = [a] }
            }
            installKeyMonitor()
        }
        .onDisappear {
            keyMonitor = nil
            reader.selectedIDs = []
            reader.anchorID = nil
            PreviewPanel.dismiss()
        }
        .onChange(of: reader.items.map(\.id.rawValue)) { _, ids in
            // Only PRUNE invalid selections — don't auto-select anything.
            // Auto-selecting after a delete is dangerous: the user just freed
            // their selection with Cmd+Delete; the next Cmd+Delete shouldn't
            // immediately wipe whatever happened to land at the top.
            reader.selectedIDs = reader.selectedIDs.intersection(ids)
            if let a = reader.anchorID, !ids.contains(a) {
                reader.anchorID = nil
            }
        }
    }

    // MARK: - Selection

    private func handleTap(id: String) {
        listFocused = true
        claimKeyWindow()
        let flags = NSApp.currentEvent?.modifierFlags ?? []
        let isCmd = flags.contains(.command)
        let isShift = flags.contains(.shift)

        if isCmd {
            if reader.selectedIDs.contains(id) {
                reader.selectedIDs.remove(id)
            } else {
                reader.selectedIDs.insert(id)
                reader.anchorID = id
            }
        } else if isShift, let anchor = reader.anchorID {
            let ids = reader.items.map(\.id.rawValue)
            if let start = ids.firstIndex(of: anchor),
               let end = ids.firstIndex(of: id) {
                let lo = min(start, end), hi = max(start, end)
                reader.selectedIDs = Set(ids[lo...hi])
            }
        } else {
            reader.selectedIDs = [id]
            reader.anchorID = id
        }
    }

    // MARK: - Key handling

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        claimKeyWindow()
        let reader = self.reader  // capture class reference — always live
        let blobs = self.blobs
        keyMonitor = NSEventMonitorHandle(local: .keyDown) { event in
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let cmd = mods.contains(.command)
            let char = event.charactersIgnoringModifiers ?? ""
            let isDeleteKey = event.keyCode == 51 || event.keyCode == 117
                || char == "\u{7F}" || char == "\u{F728}"

            if MAYNTextEditingShortcutPolicy.shouldYieldToFocusedTextInput(
                isTextEditingFirstResponder: MAYNTextEditingShortcutPolicy.isTextEditingFirstResponder(
                    in: event.window ?? NSApp.keyWindow
                ),
                keyEquivalent: char,
                modifiers: event.modifierFlags
            ) {
                return event
            }

            if cmd && isDeleteKey {  // Cmd+⌫: delete selected
                guard !reader.selectedIDs.isEmpty else { return event }
                let store = reader.store
                let initialIDs = Array(reader.selectedIDs)

                // Briefly tell the daemon to stop capturing. The daemon checks
                // `captureSuspendUntil` at the start of every poll callback —
                // this prevents ANY re-capture during the 2s window, regardless
                // of whether something (CleanShot, etc.) re-asserts pasteboard
                // ownership. Same mechanism the "Pause 60s" feature uses.
                let until = Date().addingTimeInterval(2.0).timeIntervalSince1970
                AppGroupSettings.defaults.set(until, forKey: "captureSuspendUntil")

                // Expand to include all sibling records from the same copy
                // event (within 2.0s). The daemon writes one record per
                // pasteboard representation (.png + .tiff + .fileURL for a
                // screenshot), and image blob writes can spread them across
                // hundreds of ms. Dedup hides them but leaves them in the DB.
                var allIDsSet = Set(initialIDs)
                for id in initialIDs {
                    for sibling in reader.relatedItems(toID: id) {
                        allIDsSet.insert(sibling.id.rawValue)
                    }
                }
                let idsToDelete = Array(allIDsSet)

                reader.selectedIDs = []
                reader.anchorID = nil
                Task { @MainActor in
                    guard let store else { return }
                    for idStr in idsToDelete {
                        guard let rid = RecordID(rawValue: idStr) else { continue }
                        if let body = try? store.body(for: rid),
                           case let .image(blobID, _, _) = body {
                            try? blobs.delete(id: blobID)
                        }
                        try? store.delete(id: rid)
                    }
                    NotificationCenter.default.post(name: .clipboardStoreDidChange, object: nil)
                    CopyHUD.show(initialIDs.count == 1 ? "Deleted" : "Deleted \(initialIDs.count)", symbol: "trash.fill")
                }
                return nil
            }
            if cmd && char == "a" {  // Cmd+A: select all
                let ids = reader.items.map(\.id.rawValue)
                reader.selectedIDs = Set(ids)
                reader.anchorID = ids.first
                return nil
            }
            if cmd && char == "c" {  // Cmd+C: copy anchor
                Task { @MainActor in Self.copyAndDismiss(reader: reader, blobs: blobs) }
                return nil
            }
            if event.keyCode == 53 {  // Escape: clear multi-selection (back to anchor)
                if ClipboardSystemQuickLookCoordinator.shared.isVisible {
                    ClipboardSystemQuickLookCoordinator.shared.dismiss()
                    return nil
                }
                if reader.selectedIDs.count > 1, let a = reader.anchorID {
                    reader.selectedIDs = [a]
                    return nil
                }
                return event
            }
            if event.keyCode == 36 {  // Return: copy + dismiss
                Task { @MainActor in Self.copyAndDismiss(reader: reader, blobs: blobs) }
                return nil
            }
            if event.keyCode == 49 {  // Space: preview
                if ClipboardSystemQuickLookCoordinator.shared.isVisible {
                    ClipboardSystemQuickLookCoordinator.shared.dismiss()
                } else {
                    Task { @MainActor in Self.previewAnchor(reader: reader, blobs: blobs) }
                }
                return nil
            }
            if ClipboardSystemQuickLookCoordinator.shared.isVisible, event.keyCode == 124 {  // Right arrow: next preview
                Task { @MainActor in
                    Self.moveAnchor(reader: reader, by: 1)
                    Self.previewAnchor(reader: reader, blobs: blobs)
                }
                return nil
            }
            if ClipboardSystemQuickLookCoordinator.shared.isVisible, event.keyCode == 123 {  // Left arrow: previous preview
                Task { @MainActor in
                    Self.moveAnchor(reader: reader, by: -1)
                    Self.previewAnchor(reader: reader, blobs: blobs)
                }
                return nil
            }
            if event.keyCode == 125 {  // Down arrow
                let ids = reader.items.map(\.id.rawValue)
                guard !ids.isEmpty else { return nil }
                let cur = reader.anchorID.flatMap { ids.firstIndex(of: $0) } ?? 0
                let next = min(ids.count - 1, cur + 1)
                if next != cur {
                    reader.anchorID = ids[next]
                    reader.selectedIDs = [ids[next]]
                    if ClipboardSystemQuickLookCoordinator.shared.isVisible {
                        Task { @MainActor in Self.previewAnchor(reader: reader, blobs: blobs) }
                    }
                }
                return nil
            }
            if event.keyCode == 126 {  // Up arrow
                let ids = reader.items.map(\.id.rawValue)
                guard !ids.isEmpty else { return nil }
                let cur = reader.anchorID.flatMap { ids.firstIndex(of: $0) } ?? 0
                let next = max(0, cur - 1)
                if next != cur {
                    reader.anchorID = ids[next]
                    reader.selectedIDs = [ids[next]]
                    if ClipboardSystemQuickLookCoordinator.shared.isVisible {
                        Task { @MainActor in Self.previewAnchor(reader: reader, blobs: blobs) }
                    }
                }
                return nil
            }
            return event
        }
    }

    private func claimKeyWindow() {
        // Do NOT call NSApp.activate here. When a full-screen app lives on
        // one Space and our app's other windows (main window, extra
        // NSStatusBarWindow instances on the non-fullscreen display) live on
        // the desktop Space, activating pulls macOS to that desktop Space,
        // dragging the popover along with it. The popover is already key
        // when shown by AppStatusItemController; just re-assert key on the
        // popover window itself in case SwiftUI shifted first-responder.
        for window in NSApp.windows {
            let name = String(describing: type(of: window))
            if name.contains("Popover") {
                window.makeKey()
                return
            }
        }
    }

    // MARK: - Static helpers (called from NSEvent monitor — capture reader/blobs only)

    @MainActor
    private static func moveAnchor(
        reader: LocalClipboardReader,
        by delta: Int
    ) {
        let ids = reader.items.map(\.id.rawValue)
        guard !ids.isEmpty else { return }
        let currentIdx = reader.anchorID.flatMap { ids.firstIndex(of: $0) } ?? 0
        let nextIdx = max(0, min(ids.count - 1, currentIdx + delta))
        guard nextIdx != currentIdx else { return }
        let newID = ids[nextIdx]
        reader.anchorID = newID
        reader.selectedIDs = [newID]
    }

    @MainActor
    private static func deleteSelected(reader: LocalClipboardReader, blobs: BlobStore) {
        guard let store = reader.store else { return }
        let count = reader.selectedIDs.count
        for idStr in reader.selectedIDs {
            guard let rid = RecordID(rawValue: idStr) else { continue }
            // Mirror ClipboardDockModel.deleteItem: clean image blob first
            if let body = try? store.body(for: rid),
               case let .image(blobID, _, _) = body {
                try? blobs.delete(id: blobID)
            }
            try? store.delete(id: rid)
        }
        reader.selectedIDs = []
        reader.anchorID = nil
        // Notify dock + reader so both views refresh immediately
        NotificationCenter.default.post(name: .clipboardStoreDidChange, object: nil)
        CopyHUD.show(count == 1 ? "Deleted" : "Deleted \(count)", symbol: "trash.fill")
    }

    @MainActor
    private static func copyAndDismiss(reader: LocalClipboardReader, blobs: BlobStore) {
        let id = reader.anchorID ?? reader.selectedIDs.first
        guard let id,
              let item = reader.items.first(where: { $0.id.rawValue == id }),
              let store = reader.store,
              let body = try? store.body(for: item.id)
        else { return }
        ClipboardXPCService.restoreToPasteboard(body: body, blobs: blobs, pasteboard: .general)
        NSPasteboard.general.setData(Data([0]), forType: PasteboardUTI.daemonWrite)
        Self.dismissMenuBarPopover()
        CopyHUD.show("Copied")
    }

    @MainActor
    private static func previewAnchor(
        reader: LocalClipboardReader,
        blobs: BlobStore
    ) {
        let id = reader.anchorID ?? reader.selectedIDs.first
        guard let id,
              let item = reader.items.first(where: { $0.id.rawValue == id }),
              let store = reader.store,
              let body = try? store.body(for: item.id)
        else { return }
        ClipboardSystemQuickLookCoordinator.shared.show(
            record: body,
            title: previewTitle(for: item),
            blobs: blobs
        )
    }

    /// Used by inner ScrollView's onChange (which captures self) for parity.
    private func copySelectedAndDismiss() { Self.copyAndDismiss(reader: reader, blobs: blobs) }

    private static func previewTitle(for item: ClipboardItemMeta) -> String {
        let title = (item.customLabel ?? item.preview).trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "Clipboard Preview" : title
    }

    /// Programmatically close the MenuBarExtra `.window`-style popover.
    static func dismissMenuBarPopover() {
        NotificationCenter.default.post(name: .menuBarPopoverDismissRequested, object: nil)
        for window in NSApp.windows {
            let name = String(describing: type(of: window))
            if name.contains("MenuBarExtra")
                || name.contains("NSStatusBarWindow")
                || name.contains("NSPopover") {
                window.orderOut(nil)
            }
        }
        NSApp.deactivate()
    }
}

// MARK: - Row

private struct ClipboardItemRow2: View {
    let item: ClipboardItemMeta
    let imageLoader: ImageBlobLoader
    let appIcons: AppIconResolver
    let isSelected: Bool
    let onTap: () -> Void
    let onActivate: () -> Void
    let onCopy: () -> Void

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
                    ZStack(alignment: .bottomTrailing) {
                        MenuBarImageThumbnail(
                            recordID: item.id.rawValue,
                            loader: imageLoader
                        )
                        if ClipboardHistoryIconPresentation.hasSourceApp(item) {
                            ClipboardHistoryIconView(
                                item: item,
                                fallbackSymbol: icon,
                                appIcons: appIcons,
                                size: 18,
                                symbolFontSize: 10,
                                cornerRadius: 5
                            )
                            .offset(x: 2, y: 2)
                        }
                    }
                } else {
                    ClipboardHistoryIconView(
                        item: item,
                        fallbackSymbol: icon,
                        appIcons: appIcons,
                        size: 36,
                        symbolFontSize: 16,
                        cornerRadius: 8
                    )
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
            DownloadIconButton(
                symbolName: "doc.on.doc",
                role: .secondary,
                accessibilityLabel: "Copy",
                action: onCopy
            )
            .help("Copy")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(rowBackground)
        .overlay(alignment: .leading) {
            // 3pt stripe keeps selected rows visible in the monochrome popover.
            Rectangle()
                .fill(isSelected ? Color.primary.opacity(0.65) : .clear)
                .frame(width: 3)
        }
        .onHover { isHovering = $0 }
        .onTapGesture { onTap() }
        // Double-click = activate (copy + dismiss popover). Same
        // simultaneousGesture trick as the dock carousel so the
        // single-tap doesn't wait on double-tap disambiguation.
        .simultaneousGesture(
            TapGesture(count: 2).onEnded { onActivate() }
        )
    }

    private var rowBackground: Color {
        if isSelected { return Color.primary.opacity(0.10) }
        if isHovering { return Color.primary.opacity(0.06) }
        return .clear
    }
}

// MARK: - Thumbnail

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
