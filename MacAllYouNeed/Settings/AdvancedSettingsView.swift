import AppKit
import FeatureCore
import Core
import Foundation
import SwiftUI

struct AdvancedSettingsView: View {
    let controller: AppController
    @AppStorage("betaUpdates", store: AppGroupSettings.defaults) private var beta = false
    @State private var confirmingReset = false
    @State private var confirmingFeatureReset = false
#if DEBUG
    @State private var confirmingMigrationReset = false
#endif
    var body: some View {
        MAYNSettingsPage(
            title: "Advanced",
            subtitle: "Diagnostics, reset controls, and release-channel options."
        ) {
            MAYNSection(title: "Pack management") {
                MAYNSettingsRow(
                    title: "Install pack from file…",
                    subtitle: "Side-load a feature pack zip. You will be asked for the zip's published SHA-256."
                ) {
                    MAYNButton("Install…") {
                        Task { await controller.sideloadController.presentInstallPanel(featureID: .downloader) }
                    }
                }
                MAYNDivider()
                MAYNSettingsRow(
                    title: "Feature install directory",
                    subtitle: "Reveal the folder where downloaded feature packs are stored."
                ) {
                    MAYNButton("Reveal in Finder") { openFeatureDirectory() }
                }
            }

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

            MAYNSection(title: "Setup and data") {
                MAYNSettingsRow(
                    title: "Onboarding",
                    subtitle: "Show the feature setup wizard again from the beginning."
                ) {
                    MAYNButton("Re-run onboarding…") {
                        controller.resetOnboarding()
                        controller.onboardingWindow.show()
                    }
                }
                MAYNDivider()
                MAYNSettingsRow(
                    title: "Reset all data",
                    subtitle: "Remove local databases, blobs, thumbnails, and downloader checkpoints."
                ) {
                    MAYNButton("Reset…", role: .destructive) { confirmingReset = true }
                }
#if DEBUG
                MAYNDivider()
                MAYNSettingsRow(
                    title: "Reset migration sentinel",
                    subtitle: "Clears the one-time upgrade sentinel so the What's New sheet and Migrator run again on next launch. Debug only."
                ) {
                    MAYNButton("Reset migration…", role: .destructive) { confirmingMigrationReset = true }
                }
#endif
            }

            MAYNSection(title: "Reset") {
                MAYNSettingsRow(
                    title: "Reset all features",
                    subtitle: "Disable every feature and remove downloaded asset packs. Your user data is preserved."
                ) {
                    MAYNButton("Reset…", role: .destructive) { confirmingFeatureReset = true }
                }
            }
        }
        .confirmationDialog("Reset all local data?", isPresented: $confirmingReset) {
            Button("Reset", role: .destructive) { resetAllData() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes local databases, blobs, thumbnails, and downloader checkpoints.")
        }
        .confirmationDialog("Reset all features?", isPresented: $confirmingFeatureReset) {
            Button("Reset", role: .destructive) { resetAllFeatures() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will disable every feature and remove all downloaded asset packs. Your user data (clipboard history, downloaded videos, snippets, model caches) will NOT be deleted.")
        }
#if DEBUG
        .confirmationDialog("Reset migration sentinel?", isPresented: $confirmingMigrationReset) {
            Button("Reset migration", role: .destructive) {
                MigrationSentinel.clear()
                BootstrapDefaults.clearSeeded()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The What's New sheet and Migrator will run again on the next launch. Debug only.")
        }
#endif
    }

    private func openFeatureDirectory() {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let featuresDir = appSupport
            .appendingPathComponent("MacAllYouNeed", isDirectory: true)
            .appendingPathComponent("Features", isDirectory: true)
        if !FileManager.default.fileExists(atPath: featuresDir.path) {
            try? FileManager.default.createDirectory(at: featuresDir, withIntermediateDirectories: true)
        }
        NSWorkspace.shared.activateFileViewerSelecting([featuresDir])
    }

    private func resetAllFeatures() {
        let runtime = controller.runtime
        let packInstallController = controller.packInstallController
        Task {
            for descriptor in runtime.registry.descriptors {
                try? await runtime.applyTransition(.disable, for: descriptor.id)
                if descriptor.requiresAsset {
                    try? await packInstallController.uninstall(featureID: descriptor.id)
                }
            }
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
