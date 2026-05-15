import AppKit
import Core
import Foundation
import SwiftUI

struct AdvancedSettingsView: View {
    let controller: AppController
    @AppStorage("betaUpdates", store: AppGroupSettings.defaults) private var beta = false
    @State private var confirmingReset = false
    var body: some View {
        MAYNSettingsPage(
            title: "Advanced",
            subtitle: "Diagnostics, reset controls, and release-channel options."
        ) {
            MAYNSection(title: "Updates") {
                MAYNSettingsRow(
                    title: "Beta updates",
                    subtitle: "Include pre-release builds when update checks run."
                ) {
                    Toggle("", isOn: $beta)
                        .labelsHidden()
                }
            }

            MAYNSection(title: "Diagnostics") {
                MAYNSettingsRow(
                    title: "Diagnostic bundle",
                    subtitle: "Export sanitized settings to a zip file for troubleshooting."
                ) {
                    MAYNButton("Export") { exportDiagnostics() }
                }
            }

            MAYNSection(title: "Sync") {
                MAYNSettingsRow(
                    title: "Multi-device sync",
                    subtitle: "Planned for a future phase. Current builds keep clipboard, downloads, snippets, and voice data local to this Mac."
                ) {
                    StatusPill(text: "Future", kind: .neutral)
                }
            }

            MAYNSection(title: "Setup and data") {
                MAYNSettingsRow(
                    title: "Onboarding",
                    subtitle: "Show the first-run setup flow again."
                ) {
                    MAYNButton("Re-run") { controller.resetOnboarding() }
                }
                MAYNDivider()
                MAYNSettingsRow(
                    title: "Reset all data",
                    subtitle: "Remove local databases, blobs, thumbnails, and downloader checkpoints."
                ) {
                    MAYNButton("Reset", role: .destructive) { confirmingReset = true }
                }
            }
        }
        .confirmationDialog("Reset all local data?", isPresented: $confirmingReset) {
            Button("Reset", role: .destructive) { resetAllData() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes local databases, blobs, thumbnails, and downloader checkpoints.")
        }
    }

    private func exportDiagnostics() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "MacAllYouNeed-Diagnostics.zip"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        Task.detached {
            let temp = FileManager.default.temporaryDirectory
                .appendingPathComponent("mayn-diagnostics-\(UUID())", isDirectory: true)
            try? FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
            let settings = AppGroupSettings.defaults.dictionaryRepresentation()
                .filter { !$0.key.lowercased().contains("passphrase") }
            let data = try? JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
            try? data?.write(to: temp.appendingPathComponent("settings.json"))
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
            process.arguments = ["-r", destination.path, "."]
            process.currentDirectoryURL = temp
            try? process.run()
            process.waitUntilExit()
            try? FileManager.default.removeItem(at: temp)
        }
    }

    private func resetAllData() {
        let root = AppGroup.containerURL()
        for name in ["databases", "blobs", "thumbnails", "downloader-updates", "dispatch.token"] {
            try? FileManager.default.removeItem(at: root.appendingPathComponent(name))
        }
        OnboardingState.reset()
        VoiceOnboardingProgressStore.reset()
        AppGroupSettings.defaults.removeObject(forKey: "syncFolderPath")
        AppGroupSettings.defaults.removeObject(forKey: "syncDownloadHistory")
    }
}
