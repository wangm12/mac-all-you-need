import AppKit
import ApplicationServices
import AVFoundation
import Core
import Platform
import SwiftUI

struct MainWindowRoot: View {
    let controller: AppController
    @AppStorage(MainAppDestination.storageKey, store: AppGroupSettings.defaults)
    private var selectedRaw = MainAppDestination.dashboard.rawValue
    @Environment(\.openSettings) private var openSettings

    private var selection: Binding<MainAppDestination> {
        Binding {
            MainAppDestination.storedSelection(selectedRaw)
        } set: { destination in
            selectedRaw = destination.rawValue
        }
    }

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 6) {
                Text("Mac All You Need")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.top, 18)

                ForEach(MainAppDestination.allCases) { destination in
                    MainSidebarButton(
                        destination: destination,
                        isSelected: selection.wrappedValue == destination
                    ) {
                        selection.wrappedValue = destination
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 260)
            .background(MAYNTheme.panel)
        } detail: {
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(MAYNTheme.window)
        }
        .tint(MAYNTheme.controlTint)
        .accentColor(.gray)
    }

    @ViewBuilder
    private var detailView: some View {
        switch MainAppDestination.storedSelection(selectedRaw) {
        case .dashboard:
            DashboardMainPage(controller: controller, openSettings: openSettings)
        case .clipboard:
            ClipboardMainPage(controller: controller)
        case .voice:
            VoiceSettingsView(controller: controller)
        case .downloads:
            DownloadsMainPage(controller: controller)
        case .folderPreview:
            FolderPreviewMainPage(controller: controller)
        case .snippets:
            SnippetsListView(xpc: controller.clipboardDeps.xpc)
        case .settings:
            EmbeddedSettingsView(controller: controller)
        }
    }
}

private struct MainSidebarButton: View {
    let destination: MainAppDestination
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Label(destination.title, systemImage: destination.symbolName)
                .font(.callout)
                .foregroundStyle(isSelected ? .primary : .secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(rowBackground, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }

    private var rowBackground: Color {
        if isSelected { return Color.primary.opacity(0.14) }
        if isHovering { return MAYNTheme.hover }
        return .clear
    }
}

private struct DashboardMainPage: View {
    let controller: AppController
    let openSettings: OpenSettingsAction

    var body: some View {
        MainPage(title: "Dashboard", subtitle: "A compact control surface for the app's core tools.") {
            MAYNSection(title: "Status") {
                MainStatusRow(
                    title: "Clipboard",
                    subtitle: "\(controller.clipboardReader.items.count) recent items indexed locally",
                    symbol: "doc.on.clipboard",
                    pill: StatusPill(text: "Local", kind: .neutral)
                )
                MAYNDivider()
                MainStatusRow(
                    title: "Voice",
                    subtitle: voiceSubtitle,
                    symbol: "mic",
                    pill: StatusPill(text: voiceStatusText, kind: voiceStatusKind)
                )
                MAYNDivider()
                MainStatusRow(
                    title: "Downloads",
                    subtitle: "\(controller.downloaderVM.rows.count) queue items",
                    symbol: "arrow.down.circle",
                    pill: StatusPill(text: "Ready", kind: .neutral)
                )
            }

            MAYNSection(title: "Quick actions") {
                MAYNSettingsRow(
                    title: "Open clipboard dock",
                    subtitle: "Show the bottom clipboard surface with search, paste, and snippets."
                ) {
                    Button("Open") { controller.clipboardDock.show() }
                }
                MAYNDivider()
                MAYNSettingsRow(
                    title: "Start voice dictation",
                    subtitle: "Begin recording with the configured voice shortcut behavior."
                ) {
                    Button(controller.voiceCoordinator.state == .recording ? "Stop" : "Start") {
                        if controller.voiceCoordinator.state == .recording {
                            Task { await controller.voiceCoordinator.stopRecordingAndPaste() }
                        } else {
                            Task { await controller.voiceCoordinator.startRecording() }
                        }
                    }
                    .disabled(!canToggleVoice)
                }
                MAYNDivider()
                MAYNSettingsRow(
                    title: "Browse a folder",
                    subtitle: "Open Folder Preview for a local directory."
                ) {
                    Button("Browse") { controller.folder.openPanelAndBrowse() }
                }
                MAYNDivider()
                MAYNSettingsRow(
                    title: "Settings",
                    subtitle: "Configure shortcuts, permissions, privacy, storage, and advanced options."
                ) {
                    Button("Open") {
                        NSApp.activate(ignoringOtherApps: true)
                        openSettings()
                    }
                }
            }
        }
        .task { await controller.downloaderVM.refresh() }
    }

    private var canToggleVoice: Bool {
        switch controller.voiceCoordinator.state {
        case .idle, .recording:
            true
        case .transcribing, .pasting, .error:
            false
        }
    }

    private var voiceSubtitle: String {
        if let transcript = controller.voiceCoordinator.lastTranscript {
            let text = transcript.cleanedText.isEmpty ? transcript.rawText : transcript.cleanedText
            return text.isEmpty ? "Last transcript is empty" : text
        }
        return "Ready for local dictation"
    }

    private var voiceStatusText: String {
        switch controller.voiceCoordinator.state {
        case .idle: "Ready"
        case .recording: "Listening"
        case .transcribing: "Transcribing"
        case .pasting: "Pasting"
        case .error: "Error"
        }
    }

    private var voiceStatusKind: StatusPill.Kind {
        switch controller.voiceCoordinator.state {
        case .idle: .success
        case .recording, .transcribing, .pasting: .progress
        case .error: .warning
        }
    }
}

private struct ClipboardMainPage: View {
    let controller: AppController
    @AppStorage("clipboardMaxItems", store: AppGroupSettings.defaults) private var maxItems = 10000
    @AppStorage("capture.sound", store: AppGroupSettings.defaults) private var captureSound = false
    @AppStorage("autoPaste.behavior", store: AppGroupSettings.defaults) private var pasteBehavior = "pasteIntoFocused"
    @AppStorage("autoPaste.delayMs", store: AppGroupSettings.defaults) private var pasteDelay = 150
    @State private var blockedApps: [String] = ExcludedAppsStore.load()
    @State private var hotkeyMap: [HotkeyAction: [HotkeyDescriptor]] = HotkeyMapStore.load()
    @State private var hotkeyError: String?

    var body: some View {
        MainPage(title: "Clipboard", subtitle: "Recent clipboard items captured on this Mac.") {
            MAYNSection(title: "Controls") {
                MAYNSettingsRow(
                    title: "Open clipboard dock",
                    subtitle: "Use the full bottom dock for keyboard navigation, paste, preview, and multi-select."
                ) {
                    Button("Open Dock") { controller.clipboardDock.show() }
                }
                MAYNDivider()
                MAYNSettingsRow(
                    title: "Clipboard shortcut",
                    subtitle: "Global trigger for opening the clipboard dock."
                ) {
                    HStack(spacing: 8) {
                        HotkeyRecorder(descriptor: hotkeyBinding(for: .clipboard))
                            .frame(width: 112, height: 24)
                        Button("Apply") { applyHotkeys() }
                    }
                }

                if let hotkeyError {
                    MAYNDivider()
                    MAYNSettingsRow(title: "Shortcut error") {
                        StatusPill(text: hotkeyError, kind: .danger)
                    }
                }
            }

            MAYNSection(title: "Capture") {
                MAYNSettingsRow(
                    title: "Maximum items",
                    subtitle: "Upper bound for searchable clipboard history before retention cleanup."
                ) {
                    MAYNNumericStepper(
                        text: "\(maxItems)",
                        value: $maxItems,
                        range: 100...100_000,
                        step: 100
                    )
                }
                MAYNDivider()
                MAYNSettingsRow(
                    title: "Play sound on capture",
                    subtitle: "Audible feedback when a new clipboard item is recorded."
                ) {
                    Toggle("", isOn: $captureSound)
                        .labelsHidden()
                }
                MAYNDivider()
                BundleIDExclusionEditor(bundleIDs: $blockedApps) { ExcludedAppsStore.save($0) }
            }

            MAYNSection(title: "Paste behavior") {
                MAYNSettingsRow(
                    title: "When picking an item",
                    subtitle: "Choose whether the clipboard dock inserts into the focused app or only copies."
                ) {
                    Picker("", selection: $pasteBehavior) {
                        Text("Paste into focused app").tag("pasteIntoFocused")
                        Text("Just copy").tag("copyOnly")
                        Text("Copy, then paste").tag("copyThenPaste")
                    }
                    .labelsHidden()
                    .frame(width: 190)
                }

                if pasteBehavior == "copyThenPaste" {
                    MAYNDivider()
                    MAYNSettingsRow(
                        title: "Paste delay",
                        subtitle: "Wait after copying before sending Command-V."
                    ) {
                        MAYNNumericStepper(
                            text: "\(pasteDelay) ms",
                            value: $pasteDelay,
                            range: 50...2000,
                            step: 50
                        )
                    }
                }
            }

            MAYNSection(title: "Recent items") {
                if controller.clipboardReader.items.isEmpty {
                    MAYNSettingsRow(title: "No items yet", subtitle: "Copy text, images, links, or files to start history capture.") {
                        EmptyView()
                    }
                } else {
                    ForEach(Array(controller.clipboardReader.items.prefix(12).enumerated()), id: \.element.id.rawValue) { index, item in
                        if index > 0 { MAYNDivider() }
                        MainClipboardRecentRow(
                            item: item,
                            imageLoader: controller.clipboardDeps.imageLoader
                        )
                    }
                }
            }
        }
        .onAppear {
            hotkeyMap = HotkeyMapStore.load()
            blockedApps = ExcludedAppsStore.load()
        }
    }

    private func hotkeyBinding(for action: HotkeyAction) -> Binding<HotkeyDescriptor> {
        Binding(
            get: {
                let descriptors = hotkeyMap[action] ?? [action.defaultDescriptor]
                return descriptors.first ?? action.defaultDescriptor
            },
            set: { descriptor in
                var descriptors = hotkeyMap[action] ?? [action.defaultDescriptor]
                if descriptors.isEmpty {
                    descriptors = [descriptor]
                } else {
                    descriptors[0] = descriptor
                }
                hotkeyMap[action] = descriptors
            }
        )
    }

    private func applyHotkeys() {
        do {
            try controller.applyHotkeyMap(hotkeyMap)
            HotkeyMapStore.save(hotkeyMap)
            hotkeyError = nil
        } catch {
            hotkeyError = error.localizedDescription
        }
    }
}

enum MainClipboardPreviewKind: Equatable {
    case imageThumbnail(recordID: String)
    case symbol(String)
}

enum MainClipboardItemPresentation {
    static func previewKind(for item: ClipboardItemMeta) -> MainClipboardPreviewKind {
        if item.preview.hasPrefix("(image ") {
            return .imageThumbnail(recordID: item.id.rawValue)
        }
        if item.preview.hasPrefix("http") {
            return .symbol("link")
        }
        if item.preview.hasPrefix("("), item.preview.contains("file") {
            return .symbol("doc")
        }
        return .symbol("doc.plaintext")
    }
}

private struct MainClipboardRecentRow: View {
    let item: ClipboardItemMeta
    let imageLoader: ImageBlobLoader

    var body: some View {
        switch MainClipboardItemPresentation.previewKind(for: item) {
        case let .imageThumbnail(recordID):
            MainClipboardImageRecentRow(
                item: item,
                recordID: recordID,
                imageLoader: imageLoader
            )
        case let .symbol(symbol):
            MAYNSettingsRow(
                title: item.customLabel ?? item.preview,
                subtitle: CompactTimestamp.format(item.modified)
            ) {
                Image(systemName: symbol)
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
            }
        }
    }
}

private struct MainClipboardImageRecentRow: View {
    let item: ClipboardItemMeta
    let recordID: String
    let imageLoader: ImageBlobLoader
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            MainClipboardThumbnailView(
                recordID: recordID,
                imageLoader: imageLoader,
                width: 92,
                height: 62,
                maxDim: 192
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(item.customLabel ?? "Image")
                    .font(.callout)
                Text("\(item.preview) - \(CompactTimestamp.format(item.modified))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: 82)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isHovering ? MAYNTheme.hover : Color.clear)
        .animation(MAYNMotion.normalAnimation(reduceMotion: reduceMotion), value: isHovering)
        .onHover { isHovering = $0 }
    }
}

private struct MainClipboardThumbnailView: View {
    let recordID: String
    let imageLoader: ImageBlobLoader
    let width: CGFloat
    let height: CGFloat
    let maxDim: Int
    @State private var image: NSImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(4)
            } else if failed {
                Image(systemName: "photo")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.tertiary)
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .frame(width: width, height: height)
        .background(MAYNTheme.elevated, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(MAYNTheme.subtleBorder, lineWidth: 1)
        )
        .task(id: "\(recordID)-\(maxDim)") {
            image = nil
            failed = false
            let loadedImage = await imageLoader.thumbnail(recordID: recordID, maxDim: maxDim)
            await MainActor.run {
                image = loadedImage
                failed = loadedImage == nil
            }
        }
    }
}

private struct DownloadsMainPage: View {
    let controller: AppController
    @AppStorage("downloadConcurrency", store: AppGroupSettings.defaults) private var concurrency = 3
    @AppStorage("downloadOutputTemplate", store: AppGroupSettings.defaults) private var template = "%(title)s [%(id)s].%(ext)s"
    @AppStorage("downloadDirectory", store: AppGroupSettings.defaults) private var downloadDir = ""

    private var effectivePath: String {
        if downloadDir.isEmpty {
            let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path ?? ""
            return downloads + "/MacAllYouNeed"
        }
        return downloadDir
    }

    var body: some View {
        MainPage(title: "Downloads", subtitle: "Queue media downloads and tune downloader behavior in one place.") {
            MAYNSection(title: "Queue") {
                DownloadsListView(vm: controller.downloaderVM)
                    .frame(height: 420)
            }

            MAYNSection(title: "Download settings") {
                MAYNSettingsRow(
                    title: "Concurrent downloads",
                    subtitle: "Maximum number of active downloads in the queue."
                ) {
                    MAYNNumericStepper(
                        text: "\(concurrency)",
                        value: $concurrency,
                        range: 1...10,
                        step: 1
                    )
                }
                MAYNDivider()
                MAYNSettingsRow(
                    title: "Output template",
                    subtitle: "yt-dlp filename template used for new downloads."
                ) {
                    TextField("", text: $template)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 280)
                }
                MAYNDivider()
                MAYNSettingsRow(
                    title: "Download folder",
                    subtitle: "Files are saved here unless a per-download path overrides it.",
                    minHeight: 58
                ) {
                    Text(effectivePath)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                        .font(.callout)
                        .frame(width: 260, alignment: .trailing)
                }
                MAYNDivider()
                MAYNSettingsRow(title: "Folder actions") {
                    HStack(spacing: 8) {
                        Button("Choose...") { pickFolder() }
                        Button("Reveal") {
                            NSWorkspace.shared.open(URL(fileURLWithPath: effectivePath))
                        }
                        if !downloadDir.isEmpty {
                            Button("Reset") { downloadDir = "" }
                                .foregroundStyle(.red)
                        }
                    }
                }
                MAYNDivider()
                MAYNSettingsRow(
                    title: "Downloader update",
                    subtitle: "Ask the downloader updater to check bundled yt-dlp support files."
                ) {
                    Button("Check") {
                        NotificationCenter.default.post(name: .downloaderUpdateRequested, object: nil)
                    }
                }
            }
        }
        .onChange(of: concurrency) { _, n in
            Task { await controller.downloader.queue.setMaxConcurrent(n) }
        }
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Select"
        panel.message = "Choose the folder where downloads will be saved"
        if panel.runModal() == .OK, let url = panel.url {
            downloadDir = url.path
        }
    }
}

private struct FolderPreviewMainPage: View {
    let controller: AppController
    @AppStorage("folderPreviewIncludeHidden", store: AppGroupSettings.defaults) private var includeHidden = false
    @AppStorage("folderPreviewMaxEntries", store: AppGroupSettings.defaults) private var maxEntries = 50_000

    var body: some View {
        MainPage(title: "Folder Preview", subtitle: "Browse folders and archives without leaving the app.") {
            MAYNSection(title: "Browse") {
                MAYNSettingsRow(
                    title: "Choose a folder",
                    subtitle: "Open the folder preview window with Files, Grid, and Analyze views."
                ) {
                    Button("Browse") { controller.folder.openPanelAndBrowse() }
                }
                MAYNDivider()
                MAYNSettingsRow(
                    title: "Preview home folder",
                    subtitle: FileManager.default.homeDirectoryForCurrentUser.path
                ) {
                    Button("Open") {
                        controller.folder.show(at: FileManager.default.homeDirectoryForCurrentUser)
                    }
                }
            }

            MAYNSection(title: "Preview settings") {
                MAYNSettingsRow(
                    title: "Include hidden files",
                    subtitle: "Show dotfiles and hidden entries in folder previews."
                ) {
                    Toggle("", isOn: $includeHidden)
                        .labelsHidden()
                }
                MAYNDivider()
                MAYNSettingsRow(
                    title: "Maximum entries",
                    subtitle: "Upper bound for very large folders and archives."
                ) {
                    MAYNNumericStepper(
                        text: "\(maxEntries)",
                        value: $maxEntries,
                        range: 1000...500_000,
                        step: 1000
                    )
                }
            }
        }
    }
}

private struct MainPage<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.system(size: 26, weight: .semibold))
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                content
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.vertical, 30)
        }
    }
}

private struct MainStatusRow: View {
    let title: String
    let subtitle: String
    let symbol: String
    let pill: StatusPill

    var body: some View {
        MAYNSettingsRow(title: title, subtitle: subtitle) {
            HStack(spacing: 10) {
                pill
                Image(systemName: symbol)
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
            }
        }
    }
}
