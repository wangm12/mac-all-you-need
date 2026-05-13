import AppKit
import Core
import Platform
import SwiftUI

struct DownloadsListView: View {
    @Bindable var vm: DownloaderViewModel
    @State private var showAdd = false
    @State private var addURL = ""
    @FocusState private var listFocused: Bool
    @State private var keyMonitor: Any? = nil

    var body: some View {
        VStack(spacing: 0) {
            headerBar

            if let warning = vm.cookieWarning {
                cookieWarningBanner(warning)
            }

            if showAdd {
                addURLBar
            }

            Divider()

            if vm.rows.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 28, weight: .regular))
                        .foregroundStyle(DownloadSurfaceTheme.muted)
                    Text("No downloads yet")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(DownloadSurfaceTheme.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(vm.rows, id: \.id) { record in
                            DownloadCardView(
                                record: record,
                                progress: vm.liveProgress[record.id.rawValue],
                                statusText: vm.liveStatus[record.id.rawValue],
                                isSelected: vm.selectedIDs.contains(record.id.rawValue),
                                onTap: { handleTap(id: record.id.rawValue) },
                                onPause: { Task { await vm.pause(id: record.id) } },
                                onResume: { Task { await vm.resume(id: record.id) } },
                                onRetry: { Task { await vm.retry(record: record) } },
                                onCancel: { Task { await vm.cancel(id: record.id) } },
                                onDelete: { Task { await vm.delete(ids: [record.id]) } }
                            )
                        }
                    }
                    .padding(.vertical, 4)
                }
                .background(DownloadSurfaceTheme.background)
            }
        }
        .background(DownloadSurfaceTheme.background)
        .focusable()
        .focusEffectDisabled()
        .focused($listFocused)
        .onAppear {
            listFocused = true
            installKeyMonitor()
        }
        .onDisappear {
            if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
            vm.selectedIDs = []
            vm.anchorID = nil
        }
        .task { await vm.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .addDownloadRequested)) { _ in
            showAdd = true
            if let clip = NSPasteboard.general.string(forType: .string), clip.hasPrefix("http") {
                addURL = clip
            } else {
                addURL = ""
            }
        }
    }

    private var headerBar: some View {
        HStack(spacing: 10) {
            Text("Downloads")
                .font(.system(size: 13, weight: .semibold))
            if !vm.rows.isEmpty {
                Text("\(vm.rows.count)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(DownloadSurfaceTheme.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(DownloadSurfaceTheme.fill, in: Capsule())
                    .overlay(Capsule().stroke(DownloadSurfaceTheme.border, lineWidth: 1))
            }
            Spacer()
            Button {
                showAdd.toggle()
                if showAdd {
                    if let clip = NSPasteboard.general.string(forType: .string),
                       clip.hasPrefix("http") { addURL = clip } else { addURL = "" }
                }
            } label: {
                Image(systemName: showAdd ? "xmark.circle.fill" : "plus")
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(DownloadSurfaceTheme.header)
    }

    @ViewBuilder
    private func cookieWarningBanner(_ warning: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(DownloadSurfaceTheme.warning)
            Text(warning).font(.caption).foregroundStyle(DownloadSurfaceTheme.secondary)
            Spacer()
            Button("Open Chrome") {
                NSWorkspace.shared.open(URL(string: "https://www.youtube.com")!)
            }
            .font(.caption)
            Button { vm.dismissCookieWarning() } label: {
                Image(systemName: "xmark").font(.caption2)
            }.buttonStyle(.plain).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(DownloadSurfaceTheme.warning.opacity(0.10))
        Divider()
    }

    @ViewBuilder
    private var addURLBar: some View {
        HStack(spacing: 8) {
            TextField("Paste URL…", text: $addURL).textFieldStyle(.roundedBorder)
            Button("Download") {
                let url = addURL.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !url.isEmpty else { return }
                showAdd = false; addURL = ""
                Task { await vm.add(url: url) }
            }
            .disabled(addURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .keyboardShortcut(.return)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
        .background(DownloadSurfaceTheme.header)
        Divider()
    }

    // MARK: - Key handling

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        claimKeyWindow()
        let vm = vm
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let cmd = mods.contains(.command)
            let char = event.charactersIgnoringModifiers ?? ""
            // Backspace on Mac sends keyCode 51 / "\u{7F}". Forward-Delete sends 117 / "\u{F728}".
            // Some keyboards/layouts may differ — check both keyCodes and character codes.
            let isDeleteKey = event.keyCode == 51 || event.keyCode == 117
                || char == "\u{7F}" || char == "\u{F728}"

            NSLog(
                "🔑 DL keyDown: keyCode=\(event.keyCode) char=\(char.debugDescription) cmd=\(cmd) sel=\(vm.selectedIDs.count) isDel=\(isDeleteKey)"
            )

            if cmd, isDeleteKey { // Cmd+⌫ or Cmd+⌦: delete selected
                guard !vm.selectedIDs.isEmpty else { return event }
                let ids = vm.rows.filter { vm.selectedIDs.contains($0.id.rawValue) }.map(\.id)
                vm.selectedIDs = []
                vm.anchorID = nil
                Task { @MainActor in await vm.delete(ids: ids) }
                return nil
            }
            if cmd, char == "a" { // Cmd+A: select all
                vm.selectedIDs = Set(vm.rows.map(\.id.rawValue))
                vm.anchorID = vm.rows.first?.id.rawValue
                return nil
            }
            if cmd, char == "v" { // Cmd+V: paste URL
                if let s = NSPasteboard.general.string(forType: .string)?
                    .trimmingCharacters(in: .whitespacesAndNewlines), s.hasPrefix("http")
                {
                    Task { @MainActor in await vm.add(url: s) }
                    return nil
                }
            }
            if event.keyCode == 53, !vm.selectedIDs.isEmpty { // Escape: clear selection
                vm.selectedIDs = []
                vm.anchorID = nil
                return nil
            }
            return event
        }
    }

    /// Make our MenuBarExtra panel the key window AND activate the app so key
    /// events route to our local NSEvent monitor. Cmd+Backspace specifically
    /// gets intercepted by macOS's text editing system unless the app is active.
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

    // MARK: - Selection

    private func handleTap(id: String) {
        listFocused = true
        claimKeyWindow() // re-claim after click so key events route to us, not the previous app
        let flags = NSApp.currentEvent?.modifierFlags ?? []
        let isCmd = flags.contains(.command)
        let isShift = flags.contains(.shift)

        if isCmd {
            if vm.selectedIDs.contains(id) {
                vm.selectedIDs.remove(id)
            } else {
                vm.selectedIDs.insert(id)
                vm.anchorID = id
            }
        } else if isShift, let anchor = vm.anchorID {
            let ids = vm.rows.map(\.id.rawValue)
            if let start = ids.firstIndex(of: anchor),
               let end = ids.firstIndex(of: id)
            {
                let lo = min(start, end), hi = max(start, end)
                vm.selectedIDs = Set(ids[lo ... hi])
            }
        } else {
            if vm.selectedIDs == [id] {
                vm.selectedIDs = []
                vm.anchorID = nil
            } else {
                vm.selectedIDs = [id]
                vm.anchorID = id
            }
        }
    }
}

private enum DownloadSurfaceTheme {
    static let background = Color(nsColor: .windowBackgroundColor)
    static let header = Color(nsColor: .controlBackgroundColor)
    static let rowHover = Color.primary.opacity(0.045)
    static let rowSelected = Color.primary.opacity(0.08)
    static let fill = Color.primary.opacity(0.055)
    static let border = Color.primary.opacity(0.10)
    static let strongBorder = Color.primary.opacity(0.20)
    static let secondary = Color.secondary
    static let muted = Color.secondary.opacity(0.65)
    static let progress = Color.primary.opacity(0.72)
    static let completed = Color.green.opacity(0.72)
    static let warning = Color.orange.opacity(0.78)
    static let danger = Color.red.opacity(0.78)
}

struct DownloadCardView: View {
    let record: DownloadRecord
    let progress: DownloadProgress?
    let statusText: String?
    let isSelected: Bool
    let onTap: () -> Void
    let onPause: () -> Void
    let onResume: () -> Void
    let onRetry: () -> Void
    let onCancel: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    private var overallFraction: Double {
        if record.state == .completed { return 1.0 }
        if let p = progress {
            if let dl = p.downloadedBytes, let total = p.totalBytes, total > 0 {
                return min(1, Double(dl) / Double(total))
            }
            return min(1, p.fraction)
        }
        if let total = record.bytesTotal, total > 0 {
            return min(1, Double(record.bytesDownloaded) / Double(total))
        }
        return 0
    }

    private var isMerging: Bool {
        let phase = statusText?.lowercased() ?? ""
        return phase.contains("merg") || phase.contains("remux")
    }

    private var barColor: Color {
        switch record.state {
        case .failed: DownloadSurfaceTheme.danger
        case .completed: DownloadSurfaceTheme.completed
        case .paused: DownloadSurfaceTheme.warning
        default: isMerging ? DownloadSurfaceTheme.warning : DownloadSurfaceTheme.progress
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            thumbnailView

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    stateBadge
                    Text(record.videoTitle ?? record.url)
                        .lineLimit(1)
                        .font(.system(size: 13, weight: .medium))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    actionButtons
                }

                metadataLine

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(DownloadSurfaceTheme.fill)
                        Rectangle().fill(barColor)
                            .frame(width: max(0, geo.size.width * overallFraction))
                    }
                }
                .frame(height: 2)

                captionLine
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(cardBackground)
        .overlay(
            Rectangle()
                .fill(DownloadSurfaceTheme.border)
                .frame(height: 1),
            alignment: .bottom
        )
        .overlay(
            Rectangle()
                .stroke(isSelected ? DownloadSurfaceTheme.strongBorder : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .onHover { isHovering = $0 }
    }

    private var cardBackground: some ShapeStyle {
        if isSelected { return AnyShapeStyle(DownloadSurfaceTheme.rowSelected) }
        if isHovering { return AnyShapeStyle(DownloadSurfaceTheme.rowHover) }
        return AnyShapeStyle(Color.clear)
    }

    private var thumbnailView: some View {
        Group {
            if let thumbStr = record.thumbnailURL, let thumbURL = URL(string: thumbStr) {
                AsyncImage(url: thumbURL) { img in
                    img.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    DownloadSurfaceTheme.fill
                }
            } else if record.state == .queued || record.state == .running,
                      URLDetector.videoBearingURL(in: record.url) != nil
            {
                ZStack {
                    DownloadSurfaceTheme.fill
                    ProgressView().scaleEffect(0.6)
                }
            } else if URLDetector.videoBearingURL(in: record.url) == nil {
                ZStack {
                    DownloadSurfaceTheme.fill
                    Image(systemName: "link.circle.fill")
                        .foregroundStyle(DownloadSurfaceTheme.secondary).font(.title3)
                }
            } else {
                ZStack {
                    DownloadSurfaceTheme.fill
                    Image(systemName: "video.slash")
                        .foregroundStyle(.tertiary).font(.title3)
                }
            }
        }
        .frame(width: 64, height: 40)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(DownloadSurfaceTheme.border, lineWidth: 1)
        )
    }

    private var actionButtons: some View {
        HStack(spacing: 0) {
            switch record.state {
            case .running: cardButton("pause.fill", role: .secondary, action: onPause)
            case .paused: cardButton("play.fill", role: .warning, action: onResume)
            case .queued: cardButton("xmark", role: .secondary, action: onCancel)
            case .completed:
                cardButton("folder", role: .secondary) {
                    let dir = URL(fileURLWithPath: record.destinationPath).deletingLastPathComponent()
                    NotificationCenter.default.post(name: .browseFolderRequested, object: dir)
                }
            case .failed: cardButton("arrow.counterclockwise", role: .destructive, action: onRetry)
            }
            cardButton("trash", role: .destructive, action: onDelete)
        }
    }

    private enum ButtonRole { case secondary, warning, destructive }

    private func cardButton(_ symbol: String, role: ButtonRole, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(buttonColor(for: role))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
    }

    private func buttonColor(for role: ButtonRole) -> Color {
        switch role {
        case .secondary: DownloadSurfaceTheme.secondary
        case .warning: DownloadSurfaceTheme.warning
        case .destructive: DownloadSurfaceTheme.danger
        }
    }

    private var stateBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(barColor)
                .frame(width: 5, height: 5)
            Text(stateBadgeText)
                .font(.system(size: 10, weight: .semibold))
                .textCase(.uppercase)
        }
        .foregroundStyle(record.state == .failed ? DownloadSurfaceTheme.danger : DownloadSurfaceTheme.secondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(barColor.opacity(0.10), in: Capsule())
        .overlay(Capsule().stroke(barColor.opacity(0.24), lineWidth: 1))
    }

    private var stateBadgeText: String {
        switch record.state {
        case .running: isMerging ? "Merging" : "Running"
        case .paused: "Paused"
        case .queued: "Queued"
        case .completed: "Done"
        case .failed: "Failed"
        }
    }

    @ViewBuilder
    private var metadataLine: some View {
        let parts: [String] = [record.channelName, record.durationSeconds.map { formatDuration($0) }]
            .compactMap { $0 }
        if !parts.isEmpty {
            Text(parts.joined(separator: " · "))
                .font(.system(size: 11))
                .foregroundStyle(DownloadSurfaceTheme.secondary)
        }
    }

    private var captionLine: some View {
        HStack {
            Text(stateLabel)
                .font(.system(size: 11))
                .foregroundStyle(record.state == .failed ? DownloadSurfaceTheme.danger : DownloadSurfaceTheme.secondary)
            if let speed = progress?.speedBytesPerSec, speed > 0 {
                Text("· \(ByteCountFormatter.string(fromByteCount: Int64(speed), countStyle: .file))/s")
                    .font(.system(size: 11)).foregroundStyle(DownloadSurfaceTheme.secondary)
            }
            Spacer()
            if let eta = progress?.etaSeconds, eta > 0, record.state == .running {
                Text(formatETA(eta))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var stateLabel: String {
        switch record.state {
        case .running: statusText ?? "Downloading"
        case .paused: "Paused"
        case .queued: "Queued"
        case .completed: "Completed"
        case .failed: "Failed"
        }
    }

    private func formatDuration(_ s: Int) -> String {
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }

    private func formatETA(_ s: Int) -> String {
        String(format: "ETA %d:%02d", s / 60, s % 60)
    }
}
