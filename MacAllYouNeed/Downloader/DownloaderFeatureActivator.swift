import Core
import FeatureCore
import Foundation

/// Owns the Downloader subsystem's lifecycle.
/// Wraps `DownloadCoordinator` (which embeds `DispatchServer`) for use by the feature system.
public actor DownloaderFeatureActivator: FeatureActivator {
    private var coordinator: DownloadCoordinator?
    private var dispatchServerStarted: Bool = false
    private let testMode: Bool
    private let manifestLoader: FeatureManifestLoader?

    /// `true` after a successful `activate()` call; `false` after `deactivate()`.
    public var isCoordinatorRunning: Bool { coordinator != nil }

    /// `true` once `startDispatchServer()` has completed on the coordinator.
    /// In `testMode` this is set to `true` without starting a real network listener.
    public var isDispatchServerRunning: Bool { dispatchServerStarted }

    public init(testMode: Bool = false, manifestLoader: FeatureManifestLoader? = FeatureManifestLoader.bundled()) {
        self.testMode = testMode
        self.manifestLoader = manifestLoader
    }

    public func activate() async throws {
        guard coordinator == nil else { return }   // idempotent

        // Main app owns DownloadCoordinator via AppController; only the login-item daemon
        // should allocate its own coordinator and dispatch server here.
        let isDaemon = Bundle.main.bundleIdentifier == "com.macallyouneed.app.downloader"
        guard isDaemon || testMode else {
            dispatchServerStarted = true
            return
        }

        // Resolve a binary locator. Pack locator wins if installed; legacy fallback otherwise.
        let locator: any BinaryLocator
        if let manifestLoader, let packDir = Self.installedPackDir(loader: manifestLoader) {
            locator = PackLocator(packDir: packDir)
        } else {
            locator = try LegacyBundleLocator.make()
        }

        let coord = try await MainActor.run { try DownloadCoordinator(binaries: locator) }
        coordinator = coord

        if !testMode {
            await coord.startDispatchServer()
        }
        dispatchServerStarted = true
    }

    public func deactivate() async throws {
        // Release the coordinator; its deinit cancels the DispatchServer listener.
        coordinator = nil
        dispatchServerStarted = false
    }

    /// Returns `true` if both `yt-dlp` and `ffmpeg` exist inside `packDir`.
    public static func assetPackProbe(packDir: URL) -> Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: packDir.appendingPathComponent("yt-dlp").path)
            && fm.fileExists(atPath: packDir.appendingPathComponent("ffmpeg").path)
    }

    /// Resolves the directory containing the currently-installed pack binaries.
    /// Returns nil if the pack version named by the bundled manifest is not on disk
    /// or is missing required binaries.
    public static func installedPackDir(loader: FeatureManifestLoader) -> URL? {
        guard let entry = try? loader.packEntry(forFeatureID: .downloader) else { return nil }
        let dir = AppGroup.containerURL()
            .appendingPathComponent("Features/downloader/\(entry.version)")
        guard assetPackProbe(packDir: dir) else { return nil }
        return dir
    }

    /// Detects a pre-modular install where yt-dlp/ffmpeg shipped in the wrapper bundle's
    /// Resources/ directory. If the real pack is not present on disk, write a sentinel
    /// `.present("legacy")` state so the Downloader activator can keep running off the
    /// bundled binaries until the user opts into the real pack.
    /// Returns true if migration wrote new state; false if a real pack was already present
    /// or the legacy binaries are absent.
    public static func migrateLegacyAssetStateIfNeeded(
        manager: FeatureManager,
        loader: FeatureManifestLoader,
        legacyBundleResourcesURL: URL = Bundle.main.resourceURL ?? URL(fileURLWithPath: "/")
    ) async throws -> Bool {
        // Real pack present? skip.
        if installedPackDir(loader: loader) != nil { return false }

        // Legacy binaries shipped in the bundle? mark .present("legacy").
        let fm = FileManager.default
        let legacyYt = legacyBundleResourcesURL.appendingPathComponent("yt-dlp")
        let legacyFf = legacyBundleResourcesURL.appendingPathComponent("ffmpeg")
        guard fm.fileExists(atPath: legacyYt.path), fm.fileExists(atPath: legacyFf.path) else {
            return false
        }

        let current = await manager.state(for: .downloader)
        // Don't overwrite explicit .present(<version>) -- only seed when state is asset-empty.
        switch current.assetState {
        case .notDownloaded, .downloadFailed, .notRequired:
            try await manager.markAssetState(.present(version: "legacy"), for: .downloader)
            return true
        case .present, .downloading:
            return false
        }
    }
}
