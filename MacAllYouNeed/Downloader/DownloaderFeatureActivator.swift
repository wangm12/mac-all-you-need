import FeatureCore
import Foundation

/// Owns the Downloader subsystem's lifecycle.
/// Wraps `DownloadCoordinator` (which embeds `DispatchServer`) for use by the feature system.
public actor DownloaderFeatureActivator: FeatureActivator {
    private var coordinator: DownloadCoordinator?
    private var dispatchServerStarted: Bool = false
    private let testMode: Bool

    /// `true` after a successful `activate()` call; `false` after `deactivate()`.
    public var isCoordinatorRunning: Bool { coordinator != nil }

    /// `true` once `startDispatchServer()` has completed on the coordinator.
    /// In `testMode` this is set to `true` without starting a real network listener.
    public var isDispatchServerRunning: Bool { dispatchServerStarted }

    public init(testMode: Bool = false) {
        self.testMode = testMode
    }

    public func activate() async throws {
        guard coordinator == nil else { return }   // idempotent

        // Phase 06 will add an assetPackProbe guard here before allowing activation.
        // For now the binaries live in the legacy Resources/ location and the coordinator
        // finds them via BinaryManager — so we start unconditionally.

        let coord = try DownloadCoordinator()
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
    /// Phase 06 calls this before transitioning the feature to the `enabled` state.
    public static func assetPackProbe(packDir: URL) -> Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: packDir.appendingPathComponent("yt-dlp").path)
            && fm.fileExists(atPath: packDir.appendingPathComponent("ffmpeg").path)
    }
}
