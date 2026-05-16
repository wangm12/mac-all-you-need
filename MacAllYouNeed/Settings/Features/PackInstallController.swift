import Core
import FeatureCore
import Foundation
import PackPipeline

/// Owns the on-demand install state machine for a single feature pack.
/// One controller instance is held by AppController and shared across the UI.
/// At most one install is in flight per feature; a second install request while
/// the first is running is dropped.
@MainActor
public final class PackInstallController {
    public enum InstallError: Error {
        case alreadyInFlight(FeatureID)
        case packNotInManifest(FeatureID)
    }

    private let manager: FeatureManager
    private let registry: FeatureRegistry
    private let manifestLoader: FeatureManifestLoader
    private let packDownloader: PackDownloader
    private let packInstallerOptions: PackInstaller.Options
    private var inflight: [FeatureID: Task<Void, Error>] = [:]

    public init(
        manager: FeatureManager,
        registry: FeatureRegistry,
        manifestLoader: FeatureManifestLoader,
        packDownloader: PackDownloader = PackDownloader(),
        packInstallerOptions: PackInstaller.Options = .init()
    ) {
        self.manager = manager
        self.registry = registry
        self.manifestLoader = manifestLoader
        self.packDownloader = packDownloader
        self.packInstallerOptions = packInstallerOptions
    }

    public func install(featureID: FeatureID) async throws {
        if inflight[featureID] != nil { throw InstallError.alreadyInFlight(featureID) }
        let task = Task<Void, Error> { [weak self] in
            guard let self else { return }
            try await self.runInstall(featureID: featureID)
        }
        inflight[featureID] = task
        defer { inflight[featureID] = nil }
        try await task.value
    }

    public func cancel(featureID: FeatureID) async {
        inflight[featureID]?.cancel()
        inflight[featureID] = nil
        try? await manager.markAssetState(.notDownloaded, for: featureID)
    }

    public func uninstall(featureID: FeatureID) async throws {
        let liveBaseDir = AppGroup.containerURL().appendingPathComponent("Features/\(featureID.rawValue)")
        try PackUninstaller.uninstall(featureLiveBaseDir: liveBaseDir)
        try await manager.markAssetState(.notDownloaded, for: featureID)
    }

    private func runInstall(featureID: FeatureID) async throws {
        let entry: FeaturePackManifest.PackEntry
        do {
            entry = try manifestLoader.packEntry(forFeatureID: featureID)
        } catch {
            try? await manager.markAssetState(.downloadFailed(reason: "Manifest missing pack entry: \(error)"), for: featureID)
            throw InstallError.packNotInManifest(featureID)
        }

        try await manager.markAssetState(.downloading(progress: 0.0), for: featureID)

        let stagingDir = AppGroup.containerURL().appendingPathComponent("Staging")
        try? FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        let zipURL = stagingDir.appendingPathComponent("\(featureID.rawValue)-\(entry.version).partial.zip")
        let liveBaseDir = AppGroup.containerURL().appendingPathComponent("Features/\(featureID.rawValue)")

        do {
            let managerRef = manager
            try await packDownloader.download(from: entry.url, to: zipURL) { fraction in
                Task { try? await managerRef.markAssetState(.downloading(progress: fraction), for: featureID) }
            }

            let report = try PackInstaller.install(
                packZipURL: zipURL,
                entry: entry,
                featureLiveBaseDir: liveBaseDir,
                stagingDir: stagingDir,
                options: packInstallerOptions
            )

            try? FileManager.default.removeItem(at: zipURL)
            try await manager.markAssetState(.present(version: report.installedVersion), for: featureID)
            // Auto-enable so the user does not need a second click after Install.
            try? await manager.transition(.enable, for: featureID)
        } catch {
            try? FileManager.default.removeItem(at: zipURL)
            try await manager.markAssetState(.downloadFailed(reason: "\(error)"), for: featureID)
            throw error
        }
    }
}
