import SwiftUI

struct DownloadsPopoverView: View {
    let controller: AppController

    @State private var showingDownloadURLSheet = false
    @State private var downloadURL = ""

    var body: some View {
        VStack(spacing: 0) {
            popoverHeader
            DownloadsListView(
                vm: controller.downloaderVM,
                surface: .commandCenter,
                onPasteURL: enqueueClipboardDownloadURL,
                onAddURL: { presentDownloadURLSheet(prefill: DownloaderViewModel.clipboardVideoURL()) }
            )
        }
        .sheet(isPresented: $showingDownloadURLSheet) {
            DownloadAddURLSheet(
                urlString: $downloadURL,
                onCancel: { showingDownloadURLSheet = false },
                onDownload: submitDownloadURL
            )
        }
        .background {
            DownloadPickerHost(vm: controller.downloaderVM)
        }
    }

    private var popoverHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Downloads")
                    .font(.headline.weight(.semibold))
                Text("Queue links here, paste from clipboard, or open the full Downloads page for settings and history.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            MAYNButton("Open Downloads", role: .primary, height: HotkeyChipPresentation.compactHeight) {
                controller.showMainWindow(destination: .downloads)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(MAYNTheme.panel)
    }

    private func presentDownloadURLSheet(prefill: String?) {
        downloadURL = prefill ?? ""
        showingDownloadURLSheet = true
    }

    private func submitDownloadURL(_ url: String) {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        showingDownloadURLSheet = false
        downloadURL = ""
        Task { await controller.downloaderVM.add(url: trimmed) }
    }

    private func enqueueClipboardDownloadURL() {
        Task { await controller.downloaderVM.enqueueClipboardURL() }
    }
}
