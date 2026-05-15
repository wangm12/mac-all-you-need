import AppKit
import Core
import SwiftUI

enum DownloadFilenameTemplatePreset: String, CaseIterable, Identifiable {
    case titleOnly
    case titleAndChannel
    case titleAndID
    case dateAndTitle
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .titleOnly:
            "Video title"
        case .titleAndChannel:
            "Title + channel"
        case .titleAndID:
            "Title + video ID"
        case .dateAndTitle:
            "Date + title"
        case .custom:
            "Custom pattern"
        }
    }

    var subtitle: String {
        switch self {
        case .titleOnly:
            "Simple names for personal downloads."
        case .titleAndChannel:
            "Useful when downloading from several creators."
        case .titleAndID:
            "Best for avoiding duplicate filenames."
        case .dateAndTitle:
            "Good for playlists and chronological archives."
        case .custom:
            "Write your own pattern with tokens."
        }
    }

    var template: String? {
        switch self {
        case .titleOnly:
            "%(title)s.%(ext)s"
        case .titleAndChannel:
            "%(title)s - %(uploader)s.%(ext)s"
        case .titleAndID:
            "%(title)s [%(id)s].%(ext)s"
        case .dateAndTitle:
            "%(upload_date)s - %(title)s.%(ext)s"
        case .custom:
            nil
        }
    }

    var example: String {
        guard let template else { return "My Video [abc123].mp4" }
        return Self.example(for: template)
    }

    static func matching(_ template: String) -> DownloadFilenameTemplatePreset? {
        let normalized = template.trimmingCharacters(in: .whitespacesAndNewlines)
        return allCases.first { preset in
            guard let candidate = preset.template else { return false }
            return candidate == normalized
        }
    }

    static func selection(for template: String) -> DownloadFilenameTemplatePreset {
        matching(template) ?? .custom
    }

    static func example(for template: String) -> String {
        let trimmed = template.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "My Video.mp4" }
        return trimmed
            .replacingOccurrences(of: "%(title)s", with: "My Video")
            .replacingOccurrences(of: "%(uploader)s", with: "Creator")
            .replacingOccurrences(of: "%(id)s", with: "abc123")
            .replacingOccurrences(of: "%(upload_date)s", with: "20260512")
            .replacingOccurrences(of: "%(ext)s", with: "mp4")
    }
}

struct DownloadsSettingsView: View {
    let controller: AppController
    @AppStorage("downloadConcurrency", store: AppGroupSettings.defaults) private var concurrency = 3
    @AppStorage("downloadOutputTemplate", store: AppGroupSettings.defaults) private var template = "%(title)s [%(id)s].%(ext)s"
    @AppStorage("downloadDirectory", store: AppGroupSettings.defaults) private var downloadDir = ""

    var body: some View {
        MAYNSettingsPage(
            title: "Downloads",
            subtitle: "Control downloader concurrency, file naming, and where completed media is stored."
        ) {
            MAYNSection(title: "Queue") {
                MAYNSettingsRow(
                    title: "Concurrent downloads",
                    subtitle: "Choose how many videos can download at the same time, from 1 to 10."
                ) {
                    DownloadConcurrencyDropdown(value: $concurrency)
                }
            }

            DownloadOutputSettingsSection(template: $template, downloadDir: $downloadDir)

            MAYNSection(title: "Downloader") {
                MAYNSettingsRow(
                    title: "Update check",
                    subtitle: "Ask the downloader updater to check bundled yt-dlp support files."
                ) {
                    MAYNButton("Check for update") {
                        NotificationCenter.default.post(name: .downloaderUpdateRequested, object: nil)
                    }
                }
            }
        }
        .onChange(of: concurrency) { _, n in
            Task { await controller.downloader.queue.setMaxConcurrent(n) }
        }
    }
}

enum DownloadConcurrencyControlPresentation {
    static let usesDropdown = true
    static let allowsFreeformInput = false
    static let range = 1...10
    static let options = Array(range)
    static let width: CGFloat = 78

    static func normalized(_ value: Int) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

struct DownloadConcurrencyDropdown: View {
    @Binding var value: Int

    private var normalizedValue: Binding<Int> {
        Binding {
            DownloadConcurrencyControlPresentation.normalized(value)
        } set: { nextValue in
            value = DownloadConcurrencyControlPresentation.normalized(nextValue)
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
            let normalized = DownloadConcurrencyControlPresentation.normalized(value)
            if value != normalized {
                value = normalized
            }
        }
    }
}

struct DownloadOutputSettingsSection: View {
    @Binding var template: String
    @Binding var downloadDir: String

    var body: some View {
        DownloadFilenameTemplateSection(template: $template)
        DownloadSaveLocationSection(downloadDir: $downloadDir)
    }
}

private struct DownloadFilenameTemplateSection: View {
    @Binding var template: String
    @State private var selectedPreset: DownloadFilenameTemplatePreset

    init(template: Binding<String>) {
        _template = template
        _selectedPreset = State(initialValue: DownloadFilenameTemplatePreset.selection(for: template.wrappedValue))
    }

    var body: some View {
        MAYNSection(title: "File naming") {
            MAYNSettingsRow(
                title: "Naming style",
                subtitle: "Choose a readable filename format for new downloads.",
                minHeight: 58
            ) {
                MAYNDropdown(
                    selection: $selectedPreset,
                    options: Array(DownloadFilenameTemplatePreset.allCases),
                    title: { $0.title },
                    width: MAYNControlMetrics.widePickerWidth
                )
            }
            MAYNDivider()
            MAYNSettingsRow(
                title: "Example file name",
                subtitle: selectedPreset.subtitle
            ) {
                Text(exampleFileName)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
                    .frame(width: MAYNControlMetrics.textFieldWidth, alignment: .trailing)
            }

            if selectedPreset == .custom {
                MAYNDivider()
                MAYNSettingsRow(
                    title: "Custom pattern",
                    subtitle: "Use tokens like %(title)s, %(uploader)s, %(id)s, %(upload_date)s, and %(ext)s. Keep %(ext)s at the end.",
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
                MAYNSettingsRow(
                    title: "Available tokens",
                    subtitle: "Type these into the custom pattern to include video metadata."
                ) {
                    HStack(spacing: 6) {
                        DownloadTokenChip("%(title)s")
                        DownloadTokenChip("%(uploader)s")
                        DownloadTokenChip("%(id)s")
                        DownloadTokenChip("%(ext)s")
                    }
                }
            }
        }
        .onChange(of: selectedPreset) { _, preset in
            if let pattern = preset.template {
                template = pattern
            }
        }
        .onChange(of: template) { _, value in
            guard selectedPreset != .custom else { return }
            let next = DownloadFilenameTemplatePreset.selection(for: value)
            if next != selectedPreset {
                selectedPreset = next
            }
        }
    }

    private var exampleFileName: String {
        selectedPreset == .custom
            ? DownloadFilenameTemplatePreset.example(for: template)
            : selectedPreset.example
    }
}

private struct DownloadTokenChip: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

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

private struct DownloadSaveLocationSection: View {
    @Binding var downloadDir: String

    private var effectivePath: String {
        DownloadDestinationPresentation.effectivePath(downloadDir: downloadDir)
    }

    var body: some View {
        MAYNSection(title: "Save location") {
            MAYNSettingsRow(
                title: "Download folder",
                subtitle: effectivePath,
                minHeight: 64
            ) {
                MAYNButton("Change...") { pickFolder() }
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

enum DownloadDestinationPresentation {
    static func effectivePath(downloadDir: String) -> String {
        if !downloadDir.isEmpty {
            return downloadDir
        }
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path ?? ""
        return downloads + "/MacAllYouNeed"
    }
}
