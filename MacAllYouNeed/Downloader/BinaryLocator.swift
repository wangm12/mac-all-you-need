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
