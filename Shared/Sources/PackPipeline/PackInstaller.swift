import Foundation
import FeatureCore

public enum PackInstaller {
    public struct Options: Sendable {
        public var dryRunCodesign: Bool   // true in unit tests; false in production
        public init(dryRunCodesign: Bool = false) {
            self.dryRunCodesign = dryRunCodesign
        }
    }

    public struct Report {
        public let installedVersion: String
        public let liveURL: URL
    }

    public static func install(
        packZipURL: URL,
        entry: FeaturePackManifest.PackEntry,
        featureLiveBaseDir: URL,
        stagingDir: URL,
        options: Options = .init()
    ) throws -> Report {
        let fm = FileManager.default

        // 1. Whole-zip SHA verification.
        let actualZipSha = try SHA256Hasher.hex(ofFileAt: packZipURL)
        guard actualZipSha == entry.zipSha256 else {
            throw PackPipelineError.wholeZipShaMismatch(expected: entry.zipSha256, actual: actualZipSha)
        }

        // 2. Safe extract into staging/<version>.staging
        try fm.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        let stagingVersionDir = stagingDir.appendingPathComponent("\(entry.version).staging")
        try? fm.removeItem(at: stagingVersionDir)
        let allowed = Set(entry.files.keys)
        let maxTotal = Int64(Double(entry.sizeBytes) * 1.5)
        let extractResult = try ZipExtractor.extract(
            zipFileURL: packZipURL,
            into: stagingVersionDir,
            allowedFiles: allowed,
            maxTotalBytes: maxTotal
        )

        // Post-extract: ensure every declared file actually appeared.
        for name in allowed where !extractResult.extractedFiles.contains(name) {
            try? fm.removeItem(at: stagingVersionDir)
            throw PackPipelineError.missingFile(name: name)
        }

        // 3. Per-file SHA + max-size check.
        for (name, fileEntry) in entry.files {
            let fileURL = stagingVersionDir.appendingPathComponent(name)
            let actualSha = try SHA256Hasher.hex(ofFileAt: fileURL)
            guard actualSha == fileEntry.sha256 else {
                try? fm.removeItem(at: stagingVersionDir)
                throw PackPipelineError.fileShaMismatch(name: name, expected: fileEntry.sha256, actual: actualSha)
            }
            let actualSize = (try? fm.attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber)?.int64Value ?? 0
            if actualSize > fileEntry.maxBytes {
                try? fm.removeItem(at: stagingVersionDir)
                throw PackPipelineError.fileTooLarge(name: name, declaredMax: fileEntry.maxBytes, actual: actualSize)
            }
        }

        // 4. Codesign + chmod + xattr removal for executables.
        for (name, fileEntry) in entry.files where fileEntry.executable {
            let fileURL = stagingVersionDir.appendingPathComponent(name)
            if !options.dryRunCodesign {
                try CodesignVerifier.verify(fileAt: fileURL, requirement: entry.codesignRequirement)
            }
            try setExecutable(at: fileURL)
            try QuarantineRemover.remove(at: fileURL)
        }

        // 5. Atomic rename to live path.
        try fm.createDirectory(at: featureLiveBaseDir, withIntermediateDirectories: true)
        let liveURL = featureLiveBaseDir.appendingPathComponent(entry.version)
        if fm.fileExists(atPath: liveURL.path) {
            try fm.removeItem(at: liveURL)
        }
        try fm.moveItem(at: stagingVersionDir, to: liveURL)

        return Report(installedVersion: entry.version, liveURL: liveURL)
    }

    private static func setExecutable(at url: URL) throws {
        var attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let perms = (attrs[.posixPermissions] as? NSNumber)?.intValue ?? 0o644
        attrs[.posixPermissions] = NSNumber(value: perms | 0o111)
        try FileManager.default.setAttributes(attrs, ofItemAtPath: url.path)
    }
}
