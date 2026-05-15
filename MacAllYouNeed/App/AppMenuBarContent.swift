import AppKit
import ApplicationServices
import AVFoundation
import Core
import Platform
import SwiftUI

struct AppMenuBarContent: View {
    let controller: AppController
    @State private var tab: Tab = .clipboard

    enum Tab: String, CaseIterable, Hashable, SegmentedTabDestination {
        case clipboard = "Clipboard"
        case voice = "Voice"
        case downloads = "Downloads"
        case snippets = "Snippets"

        var title: String { rawValue }

        var symbol: String {
            switch self {
            case .clipboard: "doc.on.clipboard"
            case .voice: "waveform"
            case .downloads: "arrow.down.circle"
            case .snippets: "text.quote"
            }
        }

        var symbolName: String { symbol }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Command Center")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Mac All You Need")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    controller.showMainWindow(destination: .settings)
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .background(Color.primary.opacity(0.07), in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 10)

            CommandCenterTabBar(selection: $tab)
                .padding(.horizontal, 10)
                .padding(.bottom, 10)

            Divider().overlay(Color.primary.opacity(0.12))

            Group {
                switch tab {
                case .clipboard:
                    ClipboardMenuBarContent(
                        reader: controller.clipboardReader,
                        imageLoader: controller.clipboardDeps.imageLoader,
                        appIcons: controller.clipboardDeps.appIcons,
                        blobs: controller.clipboardDeps.blobs
                    )
                case .voice:
                    VoiceCommandCenterView(controller: controller)
                case .downloads:
                    downloadsTab
                case .snippets:
                    SnippetsListView(xpc: controller.clipboardDeps.xpc)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            HStack {
                ShortcutChip(text: "⌘⇧V", height: HotkeyChipPresentation.compactHeight)
                Text("clipboard dock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                MAYNButton("Open", height: HotkeyChipPresentation.compactHeight) {
                    openSelectedTabInMainWindow()
                }
                MAYNButton("Pause 60s", height: HotkeyChipPresentation.compactHeight) {
                    controller.suspendCaptureFor60Seconds()
                }
                MAYNButton("Quit", role: .destructive, height: HotkeyChipPresentation.compactHeight) {
                    NSApp.terminate(nil)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(width: 500, height: 600)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            // Opening the menu-bar popover dismisses the dock — having both
            // visible at once is messy and the user clicked the menu icon
            // explicitly, signalling they want this surface instead.
            controller.clipboardDock.hide()
            // Also dismiss any floating preview/HUD so the popover appears
            // on a clean canvas.
            PreviewPanel.dismiss()
        }
        .onDisappear {
            PreviewPanel.dismiss()
        }
    }

    @ViewBuilder
    private var downloadsTab: some View {
        DownloadsListView(vm: controller.downloaderVM)
    }

    private func openSelectedTabInMainWindow() {
        switch tab {
        case .clipboard:
            AppGroupSettings.defaults.set(ClipboardFunctionTab.history.rawValue, forKey: ClipboardFunctionTab.storageKey)
            controller.showMainWindow(destination: .clipboard)
        case .voice:
            AppGroupSettings.defaults.set(VoiceFunctionTab.dictate.rawValue, forKey: VoiceFunctionTab.storageKey)
            controller.showMainWindow(destination: .voice)
        case .downloads:
            AppGroupSettings.defaults.set(DownloadsFunctionTab.queue.rawValue, forKey: DownloadsFunctionTab.storageKey)
            controller.showMainWindow(destination: .downloads)
        case .snippets:
            AppGroupSettings.defaults.set(SnippetsFunctionTab.library.rawValue, forKey: SnippetsFunctionTab.storageKey)
            controller.showMainWindow(destination: .snippets)
        }
    }
}

private struct CommandCenterTabBar: View {
    @Binding var selection: AppMenuBarContent.Tab

    var body: some View {
        FunctionSegmentedTabStrip(
            tabs: Array(AppMenuBarContent.Tab.allCases),
            selection: selection,
            fillsAvailableWidth: true,
            size: .control
        ) { next in
            selection = next
        }
    }
}

struct VoiceCommandCenterView: View {
    let controller: AppController

    @State private var micPermission = AVCaptureDevice.authorizationStatus(for: .audio)

    private var coordinator: VoiceCoordinator {
        controller.voiceCoordinator
    }

    private var activationSettings: VoiceActivationSettings {
        VoiceActivationSettingsStore.load()
    }

    private var asrSettings: VoiceASRSettings {
        VoiceASRSettingsStore.load()
    }

    private var onboardingProgress: VoiceOnboardingProgress {
        VoiceOnboardingProgressStore.load()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Voice")
                            .font(.system(size: 22, weight: .semibold))
                        Text(stateTitle)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    ShortcutChip(text: activationSettings.shortcut.display)
                }

                HStack(spacing: 8) {
                    VoiceCommandButton(
                        title: coordinator.state == .recording ? "Stop & Paste" : "Start",
                        symbol: coordinator.state == .recording ? "checkmark" : "mic"
                    ) {
                        if coordinator.state == .recording {
                            Task { await coordinator.stopRecordingAndPaste() }
                        } else {
                            Task { await coordinator.startRecording() }
                        }
                    }
                    .disabled(!canToggleRecording)

                    VoiceCommandButton(title: "Setup", symbol: "slider.horizontal.3") {
                        NSApp.activate(ignoringOtherApps: true)
                        controller.showVoiceOnboarding()
                    }

                    VoiceCommandButton(title: "Dictionary", symbol: "text.book.closed") {
                        AppGroupSettings.defaults.set(VoiceFunctionTab.dictionary.rawValue, forKey: VoiceFunctionTab.storageKey)
                        controller.showMainWindow(destination: .voice)
                    }

                    VoiceCommandButton(title: "Mic", symbol: "mic.badge.plus") {
                        Task { await refreshMicrophonePermission(requestIfNeeded: true) }
                    }
                    .disabled(micPermission == .authorized)
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    VoiceStatusTile(title: "Mode", value: activationSettings.mode.label, symbol: "switch.2")
                    VoiceStatusTile(title: "Language", value: asrSettings.languageHint.label, symbol: "textformat")
                    VoiceStatusTile(title: "Microphone", value: microphoneStatusText, symbol: "mic")
                    VoiceStatusTile(title: "Accessibility", value: accessibilityStatusText, symbol: "keyboard")
                    VoiceStatusTile(title: "Setup", value: onboardingProgress.isCompleted ? "Complete" : onboardingProgress.currentStep.title, symbol: "checklist")
                    VoiceStatusTile(title: "Cleanup", value: cleanupStatusText, symbol: "sparkles")
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Last transcript")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        if let transcript = coordinator.lastTranscript {
                            Text(transcript.usedLLM ? "LLM" : "Local")
                                .font(.system(size: 10, weight: .semibold))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color.primary.opacity(0.08), in: Capsule())
                        }
                    }

                    Text(lastTranscriptText)
                        .font(.system(size: 13))
                        .foregroundStyle(coordinator.lastTranscript == nil ? .tertiary : .primary)
                        .lineLimit(6)
                        .frame(maxWidth: .infinity, minHeight: 86, alignment: .topLeading)
                        .padding(12)
                        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.10), lineWidth: 1))
                }
            }
            .padding(16)
        }
        .task {
            await refreshMicrophonePermission(requestIfNeeded: false)
        }
    }

    private var canToggleRecording: Bool {
        switch coordinator.state {
        case .idle, .recording:
            true
        case .transcribing, .pasting, .error:
            false
        }
    }

    private var stateTitle: String {
        switch coordinator.state {
        case .idle:
            "Ready for dictation"
        case .recording:
            "Listening"
        case .transcribing:
            "Transcribing audio"
        case .pasting:
            "Pasting into the focused app"
        case let .error(message):
            message
        }
    }

    private var lastTranscriptText: String {
        guard let transcript = coordinator.lastTranscript else {
            return "No transcript captured yet."
        }
        return transcript.cleanedText.isEmpty ? transcript.rawText : transcript.cleanedText
    }

    private var microphoneStatusText: String {
        switch micPermission {
        case .authorized:
            "Granted"
        case .notDetermined:
            "Not requested"
        case .denied:
            "Denied"
        case .restricted:
            "Restricted"
        @unknown default:
            "Unknown"
        }
    }

    private var accessibilityStatusText: String {
        AXIsProcessTrusted() ? "Granted" : "Needs access"
    }

    private var cleanupStatusText: String {
        let settings = controller.voiceCleanupSettings()
        return settings.isEnabled ? settings.provider.label : "Local"
    }

    private func refreshMicrophonePermission(requestIfNeeded: Bool) async {
        if requestIfNeeded, micPermission == .notDetermined {
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            micPermission = granted ? .authorized : AVCaptureDevice.authorizationStatus(for: .audio)
        } else {
            micPermission = AVCaptureDevice.authorizationStatus(for: .audio)
        }
    }
}

private struct VoiceStatusTile: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 24, height: 24)
                .background(Color.primary.opacity(0.08), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                Text(value)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(minHeight: 58, alignment: .topLeading)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.10), lineWidth: 1))
    }
}

private struct VoiceCommandButton: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        MAYNButton(role: .primary, height: MAYNControlMetrics.controlHeight, action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
        }
    }
}

struct ClipboardMenuBarContent: View {
    let reader: LocalClipboardReader
    let imageLoader: ImageBlobLoader
    let appIcons: AppIconResolver
    let blobs: BlobStore

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var listFocused: Bool
    @State private var keyMonitor: Any? = nil

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
            if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
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
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
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
                Task { @MainActor in Self.previewAnchor(reader: reader, blobs: blobs) }
                return nil
            }
            if PreviewPanel.isVisible, event.keyCode == 124 {  // Right arrow: next preview
                Task { @MainActor in
                    let direction = Self.moveAnchor(reader: reader, by: 1)
                    Self.previewAnchor(reader: reader, blobs: blobs, direction: direction)
                }
                return nil
            }
            if PreviewPanel.isVisible, event.keyCode == 123 {  // Left arrow: previous preview
                Task { @MainActor in
                    let direction = Self.moveAnchor(reader: reader, by: -1)
                    Self.previewAnchor(reader: reader, blobs: blobs, direction: direction)
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
                    if PreviewPanel.isVisible {
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
                    if PreviewPanel.isVisible {
                        Task { @MainActor in Self.previewAnchor(reader: reader, blobs: blobs) }
                    }
                }
                return nil
            }
            return event
        }
    }

    private func claimKeyWindow() {
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            for window in NSApp.windows {
                let name = String(describing: type(of: window))
                if name.contains("MenuBarExtra") || name.contains("NSStatusBarWindow") {
                    window.makeKeyAndOrderFront(nil)
                    return
                }
            }
        }
    }

    // MARK: - Static helpers (called from NSEvent monitor — capture reader/blobs only)

    @MainActor
    private static func moveAnchor(
        reader: LocalClipboardReader,
        by delta: Int
    ) -> PreviewPanelTransitionDirection {
        let ids = reader.items.map(\.id.rawValue)
        guard !ids.isEmpty else { return .none }
        let currentIdx = reader.anchorID.flatMap { ids.firstIndex(of: $0) } ?? 0
        let nextIdx = max(0, min(ids.count - 1, currentIdx + delta))
        guard nextIdx != currentIdx else { return .none }
        let newID = ids[nextIdx]
        reader.anchorID = newID
        reader.selectedIDs = [newID]
        return .horizontal(from: currentIdx, to: nextIdx)
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
        blobs: BlobStore,
        direction: PreviewPanelTransitionDirection = .none
    ) {
        let id = reader.anchorID ?? reader.selectedIDs.first
        guard let id,
              let item = reader.items.first(where: { $0.id.rawValue == id }),
              let store = reader.store,
              let body = try? store.body(for: item.id)
        else { return }
        switch body {
        case let .image(blobID, _, _):
            if let data = try? blobs.read(id: blobID),
               let image = NSImage(data: data) {
                PreviewPanel.show(
                    .image(image),
                    metadata: previewMetadata(for: item, kind: "Image"),
                    direction: direction
                )
            }
        case let .files(urls) where urls.count == 1 && Self.isImageURL(urls[0]):
            if let image = NSImage(contentsOf: urls[0]) {
                PreviewPanel.show(
                    .image(image),
                    metadata: previewMetadata(for: item, kind: "File image"),
                    direction: direction
                )
            }
        case let .text(s):
            PreviewPanel.show(
                .text(s, monospaced: false),
                metadata: previewMetadata(for: item, kind: "Text"),
                direction: direction
            )
        case let .html(s):
            let plain = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            PreviewPanel.show(
                .text(plain, monospaced: false),
                metadata: previewMetadata(for: item, kind: "HTML"),
                direction: direction
            )
        case let .rtf(data):
            if let attr = NSAttributedString(rtf: data, documentAttributes: nil) {
                PreviewPanel.show(
                    .text(attr.string, monospaced: false),
                    metadata: previewMetadata(for: item, kind: "Rich text"),
                    direction: direction
                )
            }
        case .files:
            break
        }
    }

    /// Used by inner ScrollView's onChange (which captures self) for parity.
    private func copySelectedAndDismiss() { Self.copyAndDismiss(reader: reader, blobs: blobs) }

    private static func previewMetadata(
        for item: ClipboardItemMeta,
        kind: String
    ) -> PreviewPanelMetadata {
        let title = (item.customLabel ?? item.preview).trimmingCharacters(in: .whitespacesAndNewlines)
        return PreviewPanelMetadata(
            title: title.isEmpty ? kind : title,
            subtitle: "\(kind) · \(CompactTimestamp.format(item.modified))",
            badge: "Space / Esc",
            symbol: previewSymbol(for: item)
        )
    }

    private static func previewSymbol(for item: ClipboardItemMeta) -> String {
        if item.preview.hasPrefix("(image ") { return "photo" }
        if item.preview.hasPrefix("("), item.preview.contains("file") { return "doc" }
        if item.preview == "(rich text)" { return "textformat" }
        if item.preview.hasPrefix("http") { return "link" }
        return "text.alignleft"
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

    private static func isImageURL(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ["png", "jpg", "jpeg", "gif", "heic", "heif", "webp", "tiff", "tif", "bmp"].contains(ext)
    }
}

private struct ClipboardItemRow2: View {
    let item: ClipboardItemMeta
    let imageLoader: ImageBlobLoader
    let appIcons: AppIconResolver
    let isSelected: Bool
    let onTap: () -> Void
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
        Group {
            if snippets.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "text.quote")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 34, height: 34)
                        .background(MAYNTheme.selected, in: RoundedRectangle(cornerRadius: MAYNControlMetrics.cardRadius, style: .continuous))

                    VStack(spacing: 3) {
                        Text("No snippets yet")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text("Open the clipboard dock to create reusable text.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, minHeight: 160)
                .background(MAYNTheme.panel, in: RoundedRectangle(cornerRadius: MAYNControlMetrics.cardRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: MAYNControlMetrics.cardRadius, style: .continuous)
                        .stroke(MAYNTheme.subtleBorder, lineWidth: 1)
                )
                .padding(12)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(snippets) { snippet in
                            HStack(spacing: 10) {
                                Image(systemName: "text.quote")
                                    .font(.system(size: 13, weight: .semibold))
                                    .frame(width: 30, height: 30)
                                    .background(Color.primary.opacity(0.08), in: Circle())
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(snippet.name)
                                        .font(.system(size: 13, weight: .semibold))
                                    if let trigger = snippet.trigger {
                                        Text(trigger)
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                            }
                            .padding(10)
                            .background(MAYNTheme.panel, in: RoundedRectangle(cornerRadius: MAYNControlMetrics.cardRadius, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: MAYNControlMetrics.cardRadius, style: .continuous)
                                    .stroke(MAYNTheme.subtleBorder, lineWidth: 1)
                            )
                        }
                    }
                    .padding(12)
                }
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
