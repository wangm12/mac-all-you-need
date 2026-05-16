import AppKit
import Core
import FeatureCore
import Foundation
import PackPipeline

@MainActor
public final class SideloadController {
    private let manager: FeatureManager
    private let manifestLoader: FeatureManifestLoader
    private let packInstallerOptions: PackInstaller.Options

    public init(
        manager: FeatureManager,
        manifestLoader: FeatureManifestLoader,
        packInstallerOptions: PackInstaller.Options = .init()
    ) {
        self.manager = manager
        self.manifestLoader = manifestLoader
        self.packInstallerOptions = packInstallerOptions
    }

    /// Programmatic API used by tests and by the Advanced-tab button after the
    /// open-panel + SHA prompt have collected user input.
    public func install(featureID: FeatureID, zipURL: URL, userProvidedZipSha256: String) async throws {
        try await manager.markAssetState(.downloading(progress: 0.5), for: featureID)
        do {
            let manifest = try manifestLoader.load()
            let stagingDir = AppGroup.containerURL().appendingPathComponent("Staging")
            try? FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)
            let liveBaseDir = AppGroup.containerURL().appendingPathComponent("Features/\(featureID.rawValue)")
            let report = try SideloadInstaller.install(
                zipURL: zipURL,
                userProvidedZipSha256: userProvidedZipSha256,
                featurePackKey: featureID.rawValue,
                manifest: manifest,
                featureLiveBaseDir: liveBaseDir,
                stagingDir: stagingDir,
                options: packInstallerOptions
            )
            try await manager.markAssetState(.present(version: report.installedVersion), for: featureID)
            try? await manager.transition(.enable, for: featureID)
        } catch {
            try? await manager.markAssetState(.downloadFailed(reason: "\(error)"), for: featureID)
            throw error
        }
    }

    /// UI entry point. Presents an NSOpenPanel for the zip + an NSAlert text-input for the SHA-256.
    public func presentInstallPanel(featureID: FeatureID) async {
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [.zip]
        openPanel.title = "Install Pack from File"
        openPanel.message = "Choose the pack zip downloaded from MAYN's GitHub Releases."
        openPanel.allowsMultipleSelection = false
        guard openPanel.runModal() == .OK, let zipURL = openPanel.url else { return }

        let alert = NSAlert()
        alert.messageText = "Pack SHA-256"
        alert.informativeText = "Paste the zip's SHA-256 from the GitHub Release page."
        let input = NSTextField(string: "")
        input.frame = NSRect(x: 0, y: 0, width: 480, height: 24)
        alert.accessoryView = input
        alert.addButton(withTitle: "Install")
        alert.addButton(withTitle: "Cancel")
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }
        let sha = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        do {
            try await install(featureID: featureID, zipURL: zipURL, userProvidedZipSha256: sha)
            showAlert(text: "Installed", informativeText: "Pack \(featureID.rawValue) installed and enabled.")
        } catch {
            showAlert(text: "Install failed", informativeText: "\(error)")
        }
    }

    private func showAlert(text: String, informativeText: String) {
        let alert = NSAlert()
        alert.messageText = text
        alert.informativeText = informativeText
        alert.runModal()
    }
}
