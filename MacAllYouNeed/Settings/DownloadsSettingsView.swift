import AppKit
import Core
import SwiftUI

struct DownloadsSettingsView: View {
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
        MAYNSettingsPage(
            title: "Downloads",
            subtitle: "Control downloader concurrency, file naming, and where completed media is stored."
        ) {
            MAYNSection(title: "Queue") {
                MAYNSettingsRow(
                    title: "Concurrent downloads",
                    subtitle: "Maximum number of active downloads in the queue."
                ) {
                    Stepper("\(concurrency)", value: $concurrency, in: 1...10)
                        .labelsHidden()
                        .frame(width: 90)
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
            }

            MAYNSection(title: "Save location") {
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
            }

            MAYNSection(title: "Downloader") {
                MAYNSettingsRow(
                    title: "Update check",
                    subtitle: "Ask the downloader updater to check bundled yt-dlp support files."
                ) {
                    Button("Check for update") {
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
