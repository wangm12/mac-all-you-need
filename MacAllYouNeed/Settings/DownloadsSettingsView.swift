import AppKit
import Core
import os
import SwiftUI

private let downloadsSettingsLog = Logger(subsystem: Logging.subsystem(for: "downloader"), category: "settings")

// MARK: - Enums & Presentation (unchanged)

enum DownloadFilenameTemplatePreset: String, CaseIterable, Identifiable {
    case titleOnly, titleAndChannel, titleAndID, dateAndTitle, playlistCollection, custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .titleOnly: "Video title"
        case .titleAndChannel: "Title + channel"
        case .titleAndID: "Title + video ID"
        case .dateAndTitle: "Date + title"
        case .playlistCollection: "Playlist / channel batch"
        case .custom: "Custom pattern"
        }
    }

    var subtitle: String {
        switch self {
        case .titleOnly: "Simple names for personal downloads."
        case .titleAndChannel: "Useful when downloading from several creators."
        case .titleAndID: "Best for avoiding duplicate filenames."
        case .dateAndTitle: "Good for playlists and chronological archives."
        case .playlistCollection: "Organizes bulk downloads with uploader and playlist tokens."
        case .custom: "Write your own pattern with tokens."
        }
    }

    var template: String? {
        switch self {
        case .titleOnly: "%(title)s.%(ext)s"
        case .titleAndChannel: "%(title)s - %(uploader)s.%(ext)s"
        case .titleAndID: "%(title)s [%(id)s].%(ext)s"
        case .dateAndTitle: "%(upload_date)s - %(title)s.%(ext)s"
        case .playlistCollection: "%(uploader)s/%(playlist)s/%(title)s [%(id)s].%(ext)s"
        case .custom: nil
        }
    }

    var example: String {
        guard let template else { return "My Video [abc123].mp4" }
        return Self.example(for: template)
    }

    static func matching(_ template: String) -> DownloadFilenameTemplatePreset? {
        let n = template.trimmingCharacters(in: .whitespacesAndNewlines)
        return allCases.first { ($0.template ?? "") == n }
    }

    static func selection(for template: String) -> DownloadFilenameTemplatePreset {
        matching(template) ?? .custom
    }

    static func example(for template: String) -> String {
        let t = template.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return "My Video.mp4" }
        return t
            .replacingOccurrences(of: "%(title)s", with: "My Video")
            .replacingOccurrences(of: "%(uploader)s", with: "Creator")
            .replacingOccurrences(of: "%(playlist)s", with: "Summer Mix")
            .replacingOccurrences(of: "%(id)s", with: "abc123")
            .replacingOccurrences(of: "%(upload_date)s", with: "20260512")
            .replacingOccurrences(of: "%(ext)s", with: "mp4")
    }
}

enum DownloadsSettingsPresentation {
    static let bundledAssetsTitle = "Bundled downloader assets"
    static let bundledAssetsSubtitle = "yt-dlp, ffmpeg, manifest, architecture, and SHA-256 verification."
    static let interruptedRecoveryTitle = "Resume interrupted downloads on launch"
    static let interruptedRecoveryStatusText = "Automatic"
    static let filenameExampleActionTitle = "Copy"
    static let cookieProfileTitle = "Cookie profiles"
    static let cookieProfileSubtitle = "Import browser cookies or use the Companion extension for authenticated downloads."
}

enum DownloadConcurrencyControlPresentation {
    static let range = 1...10
    static let options = Array(range)
    static let width: CGFloat = 78
    static let usesDropdown = true
    static let allowsFreeformInput = false

    static func normalized(_ value: Int) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

enum DownloadDestinationPresentation {
    static func effectivePath(downloadDir: String) -> String {
        if !downloadDir.isEmpty { return downloadDir }
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path ?? ""
        return downloads + "/MacAllYouNeed"
    }
}

private enum DownloadCookieMode: String, CaseIterable {
    case browserAuto = "browser_auto"
    case extensionOnly = "extension_only"

    var title: String {
        switch self {
        case .browserAuto: "Browser Auto"
        case .extensionOnly: "Mac All You Need Companion"
        }
    }
}

private enum DownloadCookieBrowserProfile: String, CaseIterable {
    case chrome, chromium, brave, edge, safari

    var title: String {
        switch self {
        case .chrome: "Google Chrome"
        case .chromium: "Chromium"
        case .brave: "Brave"
        case .edge: "Microsoft Edge"
        case .safari: "Safari"
        }
    }
}

private enum DownloadExtensionState: String {
    case notInstalled = "not_installed"
    case installedNotSynced = "installed_not_synced"
    case synced = "synced"

    var title: String {
        switch self {
        case .notInstalled: "Not installed"
        case .installedNotSynced: "Installed, not synced"
        case .synced: "Synced"
        }
    }

    var pillKind: StatusPill.Kind {
        switch self {
        case .notInstalled: .warning
        case .installedNotSynced: .neutral
        case .synced: .success
        }
    }
}

// MARK: - Rail

private enum DownloadSettingsSection: String, CaseIterable {
    case general, naming, browser, advanced

    var label: String {
        switch self {
        case .general: "General"
        case .naming: "Naming"
        case .browser: "Browser & Cookies"
        case .advanced: "Advanced"
        }
    }

    var symbol: String {
        switch self {
        case .general: "square.grid.2x2"
        case .naming: "textformat"
        case .browser: "globe"
        case .advanced: "gearshape"
        }
    }
}

private struct DownloadSettingsRail: View {
    @Binding var selected: DownloadSettingsSection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(DownloadSettingsSection.allCases, id: \.self) { section in
                let isActive = selected == section
                Button { selected = section } label: {
                    HStack(spacing: 8) {
                        Image(systemName: section.symbol)
                            .font(.system(size: 13, weight: isActive ? .semibold : .regular))
                            .foregroundStyle(isActive ? Color.primary : Color.secondary)
                            .frame(width: 16)
                        Text(section.label)
                            .font(.callout)
                            .fontWeight(isActive ? .semibold : .regular)
                            .foregroundStyle(isActive ? Color.primary : Color.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 9)
                    .frame(minHeight: MAYNControlMetrics.controlHeight)
                    .maynSelectionBackground(
                        isSelected: isActive,
                        shape: .rounded(MAYNControlMetrics.controlRadius)
                    )
                }
                .buttonStyle(.borderless)
                .animation(MAYNMotion.controlAnimation(reduceMotion: reduceMotion), value: isActive)
            }
            Spacer()
        }
        .padding(8)
        .frame(width: 158)
        .background(MAYNTheme.window)
    }
}

// MARK: - Main View

struct DownloadsSettingsView: View {
    let controller: AppController
    @AppStorage("downloadConcurrency", store: AppGroupSettings.defaults) private var concurrency = 3
    @AppStorage("downloadOutputTemplate", store: AppGroupSettings.defaults) private var template = "%(title)s [%(id)s].%(ext)s"
    @AppStorage("downloadDirectory", store: AppGroupSettings.defaults) private var downloadDir = ""
    @State private var activeSection: DownloadSettingsSection = .general
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            DownloadSettingsRail(selected: $activeSection)

            Rectangle()
                .fill(MAYNTheme.divider)
                .frame(width: 1)

            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Downloads")
                                .font(.system(size: 24, weight: .semibold))
                            Text("Queue, naming, cookies, and engine settings.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 24)

                        VStack(spacing: 22) {
                            DownloadGeneralSection(concurrency: $concurrency, downloadDir: $downloadDir)
                                .id(DownloadSettingsSection.general)
                            DownloadNamingSection(template: $template)
                                .id(DownloadSettingsSection.naming)
                            DownloadBrowserSection(controller: controller)
                                .id(DownloadSettingsSection.browser)
                            DownloadAdvancedSection()
                                .id(DownloadSettingsSection.advanced)
                        }
                    }
                    .padding(.horizontal, 34)
                    .padding(.vertical, 28)
                    .frame(maxWidth: 760, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(MAYNTheme.window)
                .onChange(of: activeSection) { _, section in
                    withAnimation(MAYNMotion.tabAnimation(reduceMotion: reduceMotion)) {
                        proxy.scrollTo(section, anchor: .top)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: concurrency) { _, n in
            Task { await controller.downloader.queue.setMaxConcurrent(n) }
        }
    }
}

// MARK: - General

private struct DownloadGeneralSection: View {
    @Binding var concurrency: Int
    @Binding var downloadDir: String
    @AppStorage("downloadDefaultVideoQuality", store: AppGroupSettings.defaults) private var defaultQuality = 1080
    @AppStorage("downloadCollectionSubfolder", store: AppGroupSettings.defaults) private var collectionSubfolder = true
    @AppStorage("downloadAutoEnqueueSingleURL", store: AppGroupSettings.defaults) private var autoEnqueueSingleURL = false

    private var effectivePath: String { DownloadDestinationPresentation.effectivePath(downloadDir: downloadDir) }

    var body: some View {
        MAYNSection(title: "General") {
            MAYNSettingsRow(title: "Save location", minHeight: 58) {
                HStack(spacing: 10) {
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(effectivePath)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: 280, alignment: .trailing)
                        Text("New downloads are saved here.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    MAYNButton("Change…") { pickFolder() }
                }
            }
            MAYNDivider()
            MAYNSettingsRow(
                title: "Default quality",
                subtitle: "Used for playlists and collections when the format picker is skipped."
            ) {
                MAYNDropdown(
                    selection: $defaultQuality,
                    options: [144, 240, 360, 720, 1080],
                    title: { "\($0)p" },
                    width: 88
                )
            }
            MAYNDivider()
            MAYNSettingsRow(
                title: "Concurrent downloads",
                subtitle: "How many videos download at the same time."
            ) {
                DownloadConcurrencyDropdown(value: $concurrency)
            }
            MAYNDivider()
            MAYNSettingsRow(
                title: "Collection subfolders",
                subtitle: "Save playlists and profiles into a named subfolder."
            ) {
                Toggle("", isOn: $collectionSubfolder).labelsHidden()
            }
            MAYNDivider()
            MAYNSettingsRow(
                title: "Auto-download single links",
                subtitle: "Skip the format picker and use the default quality."
            ) {
                Toggle("", isOn: $autoEnqueueSingleURL).labelsHidden()
            }
        }
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Choose"
        panel.message = "Choose where new downloads should be saved."
        if panel.runModal() == .OK, let url = panel.url {
            downloadDir = url.path
        }
    }
}

// MARK: - Naming

private struct DownloadNamingSection: View {
    @Binding var template: String
    @State private var selectedPreset: DownloadFilenameTemplatePreset

    init(template: Binding<String>) {
        _template = template
        _selectedPreset = State(initialValue: DownloadFilenameTemplatePreset.selection(for: template.wrappedValue))
    }

    var body: some View {
        MAYNSection(title: "Naming") {
            MAYNSettingsRow(title: "Naming style", subtitle: selectedPreset.subtitle, minHeight: 58) {
                VStack(alignment: .trailing, spacing: 5) {
                    MAYNDropdown(
                        selection: $selectedPreset,
                        options: Array(DownloadFilenameTemplatePreset.allCases),
                        title: { $0.title },
                        width: MAYNControlMetrics.widePickerWidth
                    )
                    Text(exampleFileName)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(width: MAYNControlMetrics.widePickerWidth, alignment: .trailing)
                }
            }
            if selectedPreset == .custom {
                MAYNDivider()
                MAYNSettingsRow(
                    title: "Custom pattern",
                    subtitle: "Use tokens like %(title)s, %(uploader)s, %(id)s, %(upload_date)s, %(ext)s.",
                    minHeight: 72
                ) {
                    MAYNTextField(
                        placeholder: "%(title)s [%(id)s].%(ext)s",
                        text: $template,
                        width: MAYNControlMetrics.wideTextFieldWidth,
                        font: .system(.caption, design: .monospaced)
                    )
                }
                MAYNDivider()
                MAYNSettingsRow(title: "Available tokens", subtitle: "Insert into the pattern above.") {
                    VStack(alignment: .trailing, spacing: 6) {
                        HStack(spacing: 6) {
                            DownloadTokenChip("%(title)s")
                            DownloadTokenChip("%(uploader)s")
                            DownloadTokenChip("%(id)s")
                            DownloadTokenChip("%(ext)s")
                        }
                        HStack(spacing: 6) {
                            DownloadTokenChip("%(upload_date)s")
                            DownloadTokenChip("%(playlist)s")
                        }
                    }
                }
            }
        }
        .onChange(of: selectedPreset) { _, preset in
            if let p = preset.template { template = p }
        }
        .onChange(of: template) { _, value in
            guard selectedPreset != .custom else { return }
            let next = DownloadFilenameTemplatePreset.selection(for: value)
            if next != selectedPreset { selectedPreset = next }
        }
    }

    private var exampleFileName: String {
        selectedPreset == .custom
            ? DownloadFilenameTemplatePreset.example(for: template)
            : selectedPreset.example
    }
}

// MARK: - Browser & Cookies

private struct DownloadBrowserSection: View {
    let controller: AppController
    @AppStorage("downloadCookieMode", store: AppGroupSettings.defaults) private var cookieMode = DownloadCookieMode.browserAuto.rawValue
    @AppStorage("downloadCookieBrowserProfile", store: AppGroupSettings.defaults) private var cookieBrowserProfile = DownloadCookieBrowserProfile.chrome.rawValue
    @AppStorage("downloadExtensionState", store: AppGroupSettings.defaults) private var extensionStateRaw = DownloadExtensionState.notInstalled.rawValue
    @AppStorage("downloadExtensionSyncedAt", store: AppGroupSettings.defaults) private var extensionSyncedAt = 0.0
    @AppStorage("downloadCompanionBrowser", store: AppGroupSettings.defaults) private var companionBrowser = "Google Chrome"
    @State private var note = ""
    @State private var pingResult = ""
    @State private var setupExpanded = false

    private static let allBrowserOptions = [
        "Google Chrome", "Google Chrome Beta", "Google Chrome Canary",
        "Google Chrome Dev", "Chromium", "Microsoft Edge", "Brave Browser",
    ]

    private static var installedBrowserOptions: [String] {
        let fm = FileManager.default
        let dirs = ["/Applications", (NSHomeDirectory() as NSString).appendingPathComponent("Applications")]
        let installed = allBrowserOptions.filter { name in dirs.contains { fm.fileExists(atPath: "\($0)/\(name).app") } }
        return installed.isEmpty ? allBrowserOptions : installed
    }

    private var extensionState: DownloadExtensionState {
        DownloadExtensionState(rawValue: extensionStateRaw) ?? .notInstalled
    }

    private var companionStatusLine: String {
        switch extensionState {
        case .notInstalled:
            return "Not installed — follow the setup steps to get started."
        case .installedNotSynced:
            return "Extension found but cookies not yet synced. Run Step 3."
        case .synced:
            guard extensionSyncedAt > 0 else { return "Cookies synced." }
            let fmt = RelativeDateTimeFormatter()
            fmt.unitsStyle = .full
            return "Cookies synced \(fmt.localizedString(for: Date(timeIntervalSince1970: extensionSyncedAt), relativeTo: Date())). Browser: \(companionBrowser)."
        }
    }

    var body: some View {
        MAYNSection(title: "Browser & Cookies") {
            VStack(spacing: 0) {
                browserSettingsRow(
                    icon: "cookie",
                    title: "Cookie source",
                    subtitle: "Use Automatic for most sites. Browser is chosen in the Companion section below."
                ) {
                    MAYNDropdown(
                        selection: $cookieMode,
                        options: DownloadCookieMode.allCases.map(\.rawValue),
                        title: { DownloadCookieMode(rawValue: $0)?.title ?? $0 },
                        width: 180
                    )
                }
                MAYNDivider()
                companionCard
            }
            .background(
                RoundedRectangle(cornerRadius: MAYNControlMetrics.cardRadius, style: .continuous)
                    .fill(MAYNTheme.elevated.opacity(0.35))
            )
            .overlay(
                RoundedRectangle(cornerRadius: MAYNControlMetrics.cardRadius, style: .continuous)
                    .stroke(MAYNTheme.subtleBorder, lineWidth: 1)
            )
        }
        .onAppear {
            refreshState()
            syncInstalledCompanionBrowser()
            syncCookieProfileFromCompanionBrowser()
        }
        .onChange(of: companionBrowser) { _, _ in
            syncCookieProfileFromCompanionBrowser()
        }
    }

    /// Picks the first installed Chromium browser for Companion setup/sync.
    private func syncInstalledCompanionBrowser() {
        let installed = Self.installedBrowserOptions
        if !installed.contains(companionBrowser), let first = installed.first {
            companionBrowser = first
        }
    }

    /// Browser Auto import follows the Companion browser selection (no separate profile row).
    private func syncCookieProfileFromCompanionBrowser() {
        cookieBrowserProfile = Self.cookieProfileKey(forCompanionBrowser: companionBrowser)
    }

    private static func cookieProfileKey(forCompanionBrowser browser: String) -> String {
        let lower = browser.lowercased()
        if lower.contains("edge") { return DownloadCookieBrowserProfile.edge.rawValue }
        if lower.contains("brave") { return DownloadCookieBrowserProfile.brave.rawValue }
        if lower == "chromium" { return DownloadCookieBrowserProfile.chromium.rawValue }
        if lower.contains("safari") { return DownloadCookieBrowserProfile.safari.rawValue }
        return DownloadCookieBrowserProfile.chrome.rawValue
    }

    private func browserSettingsRow<T: View>(
        icon: String,
        title: String,
        subtitle: String,
        @ViewBuilder trailing: () -> T
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: MAYNControlMetrics.controlRadius, style: .continuous)
                    .fill(MAYNTheme.elevated)
                    .overlay(
                        RoundedRectangle(cornerRadius: MAYNControlMetrics.controlRadius, style: .continuous)
                            .stroke(MAYNTheme.subtleBorder, lineWidth: 1)
                    )
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            trailing()
        }
        .padding(.horizontal, MAYNControlMetrics.rowHorizontalPadding)
        .padding(.vertical, 10)
    }

    private var companionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text("Mac All You Need Companion")
                            .font(.callout.weight(.semibold))
                        Button("Learn more") {
                            _ = openInBrowser("https://support.google.com/chrome")
                        }
                        .font(.caption.weight(.medium))
                        .buttonStyle(.plain)
                        .foregroundStyle(MAYNTheme.progress)
                    }
                    Text(companionStatusLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                StatusPill(text: extensionState.title, kind: extensionState.pillKind)
            }

            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: MAYNControlMetrics.controlRadius, style: .continuous)
                            .fill(MAYNTheme.elevated)
                            .overlay(
                                RoundedRectangle(cornerRadius: MAYNControlMetrics.controlRadius, style: .continuous)
                                    .stroke(MAYNTheme.subtleBorder, lineWidth: 1)
                            )
                        Image(systemName: "globe")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 38, height: 38)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Browser")
                            .font(.callout.weight(.semibold))
                        Text("Auto-detected for cookie import, extension setup, and sync.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    MAYNDropdown(
                        selection: $companionBrowser,
                        options: Self.installedBrowserOptions,
                        title: { $0 },
                        width: 220
                    )
                    Spacer(minLength: 0)
                }

                HStack(alignment: .top, spacing: 10) {
                    companionActionCard(
                        icon: "arrow.triangle.2.circlepath",
                        title: "Sync Now",
                        subtitle: "Sync cookies instantly"
                    ) { openSyncPage() }
                    companionActionCard(
                        icon: "wifi",
                        title: "Check Connection",
                        subtitle: "Verify Companion is connected"
                    ) { Task { await checkPing() } }
                    companionActionCard(
                        icon: "puzzlepiece.extension",
                        title: "Manage Extension",
                        subtitle: "Open extension folder"
                    ) { openExtensionsPage() }
                    companionActionCard(
                        icon: "arrow.counterclockwise",
                        title: "Reset Registration",
                        subtitle: "Clear stale token"
                    ) { Task { await resetCompanionRegistration() } }
                    companionActionCard(
                        icon: "arrow.clockwise",
                        title: "Refresh Status",
                        subtitle: "Update sync state"
                    ) { refreshState() }
                }
            }
            .padding(14)
            .background(
                MAYNTheme.window.opacity(0.78),
                in: RoundedRectangle(cornerRadius: MAYNControlMetrics.controlRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: MAYNControlMetrics.controlRadius, style: .continuous)
                    .stroke(MAYNTheme.subtleBorder, lineWidth: 1)
            )

            if !note.isEmpty || !pingResult.isEmpty {
                Text(note.isEmpty ? pingResult : note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            DisclosureGroup("Setup steps", isExpanded: $setupExpanded) {
                VStack(alignment: .leading, spacing: 8) {
                    setupStep(number: "1", label: "Open the extension folder in Finder.") {
                        MAYNButton("Open Folder") { openFolder() }
                    }
                    setupStep(number: "2", label: "In \(companionBrowser): enable Developer mode → Load unpacked → select the folder.") {
                        MAYNButton("Extensions Page") { openExtensionsPage() }
                    }
                    setupStep(number: "3", label: "Sync cookies. Keep the browser open until status shows Synced.") {
                        MAYNButton("Sync") { openSyncPage() }
                    }
                }
                .padding(.top, 6)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .padding(.horizontal, MAYNControlMetrics.rowHorizontalPadding)
        .padding(.bottom, MAYNControlMetrics.rowVerticalPadding)
    }

    private func companionActionCard(
        icon: String,
        title: String,
        subtitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: MAYNControlMetrics.controlRadius, style: .continuous)
                        .fill(MAYNTheme.elevated)
                        .overlay(
                            RoundedRectangle(cornerRadius: MAYNControlMetrics.controlRadius, style: .continuous)
                                .stroke(MAYNTheme.subtleBorder, lineWidth: 1)
                        )
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 54, maxHeight: 54, alignment: .leading)
            .background(MAYNTheme.elevated, in: RoundedRectangle(cornerRadius: MAYNControlMetrics.controlRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: MAYNControlMetrics.controlRadius, style: .continuous)
                    .stroke(MAYNTheme.subtleBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func setupStep<T: View>(number: String, label: String, @ViewBuilder trailing: () -> T) -> some View {
        HStack(alignment: .center, spacing: 8) {
            ZStack {
                Circle()
                    .fill(MAYNTheme.elevated)
                    .overlay(Circle().stroke(MAYNTheme.subtleBorder, lineWidth: 1))
                Text(number)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 18, height: 18)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            trailing()
        }
    }

    private func openFolder() {
        guard let path = bundledExtensionPath() else {
            note = "Bundled Companion folder is missing from the app bundle."; return
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
        note = "Folder opened. Now load it in \(companionBrowser) (Step 2)."
        refreshState()
    }

    private func openExtensionsPage() {
        let url = companionBrowser.lowercased().contains("edge") ? "edge://extensions" : "chrome://extensions"
        if !openInBrowser(url) {
            note = "Could not open \(companionBrowser). Open its extensions page manually."
        }
    }

    private func openSyncPage() {
        if openInBrowser("http://127.0.0.1:18765/cookie-sync-landing") {
            note = "Sync page opened in \(companionBrowser). Keep it open until status shows Synced."
        } else {
            note = "Could not open \(companionBrowser). Open http://127.0.0.1:18765/cookie-sync-landing manually."
        }
    }

    private func resetCompanionRegistration() async {
        await controller.downloader.resetCompanionRegistration()
        extensionStateRaw = DownloadExtensionState.installedNotSynced.rawValue
        note = "Companion registration cleared. Click Sync Now to re-register and sync cookies."
        pingResult = ""
    }

    private func refreshState() {
        let fm = FileManager.default
        let cookieFile = AppGroup.containerURL().appendingPathComponent("cookies/downloader-extension-cookies.txt")
        let path = bundledExtensionPath()
        let next: DownloadExtensionState
        if path == nil {
            next = .notInstalled
        } else if fm.fileExists(atPath: cookieFile.path) {
            next = .synced
            extensionSyncedAt = Date().timeIntervalSince1970
        } else {
            next = .installedNotSynced
        }
        extensionStateRaw = next.rawValue
        note = ""
        pingResult = ""
    }

    private func checkPing() async {
        guard let url = URL(string: "http://127.0.0.1:18765/ping") else { return }
        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            pingResult = (response as? HTTPURLResponse)?.statusCode == 200
                ? "✓ App reachable on localhost:18765"
                : "App returned an unexpected status."
        } catch {
            pingResult = "Not reachable — make sure the app is running."
        }
    }

    @discardableResult
    private func openInBrowser(_ rawURL: String) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = ["-a", companionBrowser, rawURL]
        do {
            try p.run(); p.waitUntilExit()
            if p.terminationStatus == 0 { return true }
        } catch {
            downloadsSettingsLog.debug("open -a \(companionBrowser, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        }
        if rawURL.hasPrefix("http"), let url = URL(string: rawURL) {
            return NSWorkspace.shared.open(url)
        }
        return false
    }

    private func bundledExtensionPath() -> String? {
        if let bundled = Bundle.main.resourceURL?
            .appendingPathComponent("Onboarding", isDirectory: true)
            .appendingPathComponent("DownloaderChromeExtension", isDirectory: true),
           FileManager.default.fileExists(atPath: bundled.path)
        { return bundled.path }
        let fallback = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Resources/Onboarding/DownloaderChromeExtension", isDirectory: true)
        return FileManager.default.fileExists(atPath: fallback.path) ? fallback.path : nil
    }
}

// MARK: - Advanced

private struct DownloadAdvancedSection: View {
    @AppStorage("downloadConcurrentFragments", store: AppGroupSettings.defaults) private var concurrentFragments = 4
    @AppStorage("downloadSpeedMode", store: AppGroupSettings.defaults) private var speedMode = "balanced"
    @AppStorage("downloadSleepInterval", store: AppGroupSettings.defaults) private var sleepInterval = 0.0

    var body: some View {
        MAYNSection(title: "Advanced") {
            MAYNSettingsRow(
                title: "Speed mode",
                subtitle: "Controls retry pacing for unstable streams."
            ) {
                MAYNDropdown(
                    selection: $speedMode,
                    options: ["balanced", "gentle", "turbo"],
                    title: { $0.capitalized },
                    width: 108
                )
            }
            MAYNDivider()
            MAYNSettingsRow(
                title: "Download fragments",
                subtitle: "Higher values can improve HLS speed but may increase throttling. Douyin is always capped at 2."
            ) {
                MAYNDropdown(
                    selection: $concurrentFragments,
                    options: [1, 2, 4, 8, 12],
                    title: { "\($0)" },
                    width: 88
                )
            }
            MAYNDivider()
            MAYNSettingsRow(
                title: "Delay between requests",
                subtitle: "Reduces burst rate for sites with strict throttling."
            ) {
                MAYNDropdown(
                    selection: $sleepInterval,
                    options: [0.0, 0.25, 0.5, 1.0],
                    title: { $0 == 0 ? "Off" : String(format: "%.2gs", $0) },
                    width: 88
                )
            }
            MAYNDivider()
            MAYNSettingsRow(
                title: DownloadsSettingsPresentation.bundledAssetsTitle,
                subtitle: DownloadsSettingsPresentation.bundledAssetsSubtitle
            ) {
                MAYNButton("Check") {
                    NotificationCenter.default.post(name: .downloaderUpdateRequested, object: nil)
                }
            }
        }
    }
}

// MARK: - Reusable controls

struct DownloadConcurrencyDropdown: View {
    @Binding var value: Int

    private var normalizedValue: Binding<Int> {
        Binding {
            DownloadConcurrencyControlPresentation.normalized(value)
        } set: { v in
            value = DownloadConcurrencyControlPresentation.normalized(v)
        }
    }

    var body: some View {
        MAYNDropdown(
            selection: normalizedValue,
            options: DownloadConcurrencyControlPresentation.options,
            title: { "\($0)" },
            width: DownloadConcurrencyControlPresentation.width
        )
        .onAppear {
            let n = DownloadConcurrencyControlPresentation.normalized(value)
            if value != n { value = n }
        }
    }
}

// Compatibility shim — used by DownloadsDestinationView as an embedded settings panel.
struct DownloadsSettingsContent: View {
    let controller: AppController
    @Binding var concurrency: Int
    @Binding var template: String
    @Binding var downloadDir: String

    var body: some View {
        DownloadGeneralSection(concurrency: $concurrency, downloadDir: $downloadDir)
        DownloadNamingSection(template: $template)
        DownloadBrowserSection(controller: controller)
        DownloadAdvancedSection()
    }
}

struct DownloadOutputSettingsSection: View {
    @Binding var template: String
    @Binding var downloadDir: String

    var body: some View {
        DownloadNamingSection(template: $template)
    }
}

private struct DownloadTokenChip: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(.caption2, design: .monospaced))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(MAYNTheme.elevated, in: RoundedRectangle(cornerRadius: MAYNControlMetrics.controlRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: MAYNControlMetrics.controlRadius, style: .continuous)
                    .stroke(MAYNTheme.subtleBorder, lineWidth: 1)
            )
    }
}
