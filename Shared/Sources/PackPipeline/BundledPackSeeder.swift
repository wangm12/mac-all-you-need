import FeatureCore
import Foundation

/// Copies feature binaries from the app bundle into the App Group live path when
/// the bundled manifest still has dev placeholder release metadata.
public enum BundledPackSeeder {
    public struct Report: Sendable, Equatable {
        public let installedVersion: String
        public let liveURL: URL

        public init(installedVersion: String, liveURL: URL) {
            self.installedVersion = installedVersion
            self.liveURL = liveURL
        }
    }

    public static func isAlreadyInstalled(entry: FeaturePackManifest.PackEntry, liveBaseDir: URL) -> Bool {
        probePackDir(liveBaseDir.appendingPathComponent(entry.version))
    }

    /// Seeds the downloader pack from `bundleResourcesURL` when the manifest entry is a dev placeholder.
    public static func seedIfPossible(
        featureID: FeatureID,
        entry: FeaturePackManifest.PackEntry,
        bundleResourcesURL: URL,
        liveBaseDir: URL
    ) throws -> Report? {
        guard entry.isDevPlaceholder, featureID == .downloader else { return nil }

        let fm = FileManager.default
        let yt = bundleResourcesURL.appendingPathComponent("yt-dlp")
        let ff = bundleResourcesURL.appendingPathComponent("ffmpeg")
        guard fm.fileExists(atPath: yt.path), fm.fileExists(atPath: ff.path) else { return nil }

        let liveURL = liveBaseDir.appendingPathComponent(entry.version)
        if fm.fileExists(atPath: liveURL.path) {
            try fm.removeItem(at: liveURL)
        }
        try fm.createDirectory(at: liveURL, withIntermediateDirectories: true)

        for (source, name) in [(yt, "yt-dlp"), (ff, "ffmpeg")] {
            let destination = liveURL.appendingPathComponent(name)
            try fm.copyItem(at: source, to: destination)
            try QuarantineRemover.remove(at: destination)
            try setExecutable(at: destination)
        }

        return Report(installedVersion: entry.version, liveURL: liveURL)
    }

    private static func probePackDir(_ packDir: URL) -> Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: packDir.appendingPathComponent("yt-dlp").path)
            && fm.fileExists(atPath: packDir.appendingPathComponent("ffmpeg").path)
    }

    private static func setExecutable(at url: URL) throws {
        var attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let perms = (attrs[.posixPermissions] as? NSNumber)?.intValue ?? 0o644
        attrs[.posixPermissions] = NSNumber(value: perms | 0o111)
        try FileManager.default.setAttributes(attrs, ofItemAtPath: url.path)
    }
}
