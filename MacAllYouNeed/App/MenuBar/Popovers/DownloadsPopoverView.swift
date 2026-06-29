import SwiftUI

struct DownloadsPopoverView: View {
    let controller: AppController

    @State private var showingDownloadURLSheet = false
    @State private var downloadURL = ""

    var body: some View {
        VStack(spacing: 0) {
            CommandCenterPageHeader(
                title: "Downloads",
                subtitle: "Manage active downloads, failed items, and saved media.",
                actionTitle: "Open Downloads",
                onAction: {
                    controller.showMainWindow(destination: .downloads)
                }
            )
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
