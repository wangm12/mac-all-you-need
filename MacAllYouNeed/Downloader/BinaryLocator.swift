@preconcurrency import Core
import Foundation

/// Resolves the on-disk paths of the Downloader's external binaries (yt-dlp, ffmpeg).
/// Two implementations: LegacyBundleLocator for the pre-modular Resources/ layout,
/// PackLocator for the on-demand Features/downloader/<version>/ layout.
public protocol BinaryLocator: Sendable {
    func ytdlpPath() throws -> URL
    func ffmpegPath() throws -> URL
}

public struct LegacyBundleLocator: BinaryLocator {
    public let binaries: BinaryManager
    public init(binaries: BinaryManager) { self.binaries = binaries }

    public static func make(bundleResources: URL? = nil) throws -> LegacyBundleLocator {
        if let bundleResources {
            try BinaryManager.installSharedBinariesIfNeeded(bundleResources: bundleResources)
            return LegacyBundleLocator(binaries: BinaryManager(bundleResources: bundleResources))
        }
        try BinaryManager.installSharedBinariesFromBundleIfNeeded()
        // After seeding, the BinaryManager resolves yt-dlp/ffmpeg from the App Group
        // shared directory first, so any non-nil Resources URL is a safe fallback base
        // even for the binary-free DownloadDaemon bundle.
        let resources = BinaryManager.seedResourcesURL()
            ?? Bundle.main.resourceURL
            ?? BinaryManager.wrapperAppResourcesURL()
            ?? BinaryManager.sharedBinariesDirectory()
        return LegacyBundleLocator(binaries: BinaryManager(bundleResources: resources))
    }

    public func ytdlpPath() throws -> URL { try binaries.ytdlpPath() }
    public func ffmpegPath() throws -> URL { try binaries.ffmpegPath() }
}

public struct PackLocator: BinaryLocator {
    public enum LocatorError: Error {
        case binaryNotInPack(name: String, packDir: URL)
    }

    public let packDir: URL
    public init(packDir: URL) { self.packDir = packDir }

    public func ytdlpPath() throws -> URL { try resolve("yt-dlp") }
    public func ffmpegPath() throws -> URL { try resolve("ffmpeg") }

    private func resolve(_ name: String) throws -> URL {
        let url = packDir.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw LocatorError.binaryNotInPack(name: name, packDir: packDir)
        }
        return url
    }
}
