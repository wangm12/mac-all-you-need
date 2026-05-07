import AppKit
import Core
import SwiftUI

struct SyncSettingsView: View {
    let controller: AppController
    @AppStorage("syncFolderPath", store: AppGroupSettings.defaults) private var syncFolderPath: String = ""
    @AppStorage("syncDownloadHistory", store: AppGroupSettings.defaults) private var syncDownloads = false
    var body: some View {
        Form {
            HStack {
                Text("Sync folder")
                Spacer()
                Text(syncFolderPath.isEmpty ? "Not set" : syncFolderPath).foregroundStyle(.secondary)
                Button("Pick…") { pick() }
            }
            if !syncFolderPath.isEmpty {
                CloudDetectionChip(path: syncFolderPath)
                Toggle("Sync download history", isOn: $syncDownloads)
            }
            if syncFolderPath.isEmpty {
                Text("Sync requires Plan 2 — coming soon.").font(.caption).foregroundStyle(.tertiary)
            }
        }.padding()
    }

    private func pick() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        if panel.runModal() == .OK, let url = panel.url {
            syncFolderPath = url.path
            Task { await controller.startSyncIfConfigured() }
        }
    }
}

struct CloudDetectionChip: View {
    let path: String
    var detection: String {
        if path.contains("Mobile Documents") { return "iCloud Drive · ~30s sync" }
        if path.contains("Google Drive") || path.contains("GoogleDrive") { return "Google Drive · ~5s sync" }
        if path.contains("Dropbox") { return "Dropbox · ~2s sync" }
        if path.contains("OneDrive") { return "OneDrive · ~30s sync" }
        return "Local folder · no sync"
    }
    var body: some View {
        Label(detection, systemImage: "cloud").foregroundStyle(.secondary)
    }
}
