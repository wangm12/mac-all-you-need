import CryptoKit
import Foundation

public enum BinaryManagerError: Error, Equatable {
    case missing(String)
    case hashMismatch(String)
    case notExecutable
    case missingArchitecture(String)
    case missingManifest
    case invalidManifest
}

private struct BinaryManifest: Decodable {
    struct Tool: Decodable { let version: String; let sha256: String }
    let ytdlp: Tool
    let ffmpeg: Tool
    enum CodingKeys: String, CodingKey {
        case ytdlp = "yt-dlp"
        case ffmpeg
    }
}

public final class BinaryManager {
    public static let sharedBinaryNames = ["yt-dlp", "ffmpeg"]
    public static let manifestFileName = "downloader-manifest.json"

    public let bundleResources: URL
    public let updateRoot: URL
    private let log = Logging.logger(for: "downloader", category: "binaries")

    public static func sharedBinariesDirectory() -> URL {
        AppGroup.containerURL().appendingPathComponent("binaries", isDirectory: true)
    }

    /// True when the App Group `binaries/` directory already holds a manifest and
    /// both binaries that verify against it. Used to make seeding idempotent and
    /// to let a login item start from a previous session's shared copies even when
    /// its own bundle no longer ships the binaries.
    public static func sharedBinariesVerified() -> Bool {
        let destination = sharedBinariesDirectory()
        let manifestURL = destination.appendingPathComponent(manifestFileName)
        guard FileManager.default.fileExists(atPath: manifestURL.path),
              let manifest = try? JSONDecoder().decode(BinaryManifest.self, from: Data(contentsOf: manifestURL))
        else {
            return false
        }
        for name in sharedBinaryNames {
            let target = destination.appendingPathComponent(name)
            let expected = name == "yt-dlp" ? manifest.ytdlp.sha256 : manifest.ffmpeg.sha256
            guard FileManager.default.fileExists(atPath: target.path),
                  (try? verify(at: target, expectedSHA256: expected)) != nil
            else {
                return false
            }
        }
        return true
    }

    /// Copies bundled downloader binaries into the App Group when missing or stale.
    /// Both the main app and DownloadDaemon call this before resolving paths.
    ///
    /// No-ops when the shared copies already verify. Serialized with an exclusive
    /// file lock so a concurrent main-app launch and daemon login do not race on
    /// the same destination paths.
    public static func installSharedBinariesIfNeeded(bundleResources: URL) throws {
        let destination = sharedBinariesDirectory()
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        if sharedBinariesVerified() { return }

        try withInstallLock(in: destination) {
            // Re-check inside the lock: another process may have just finished.
            if sharedBinariesVerified() { return }

            let manifestURL = bundleResources.appendingPathComponent(manifestFileName)
            guard FileManager.default.fileExists(atPath: manifestURL.path) else {
                throw BinaryManagerError.missingManifest
            }
            let manifest = try JSONDecoder().decode(BinaryManifest.self, from: Data(contentsOf: manifestURL))

            for name in sharedBinaryNames {
                let source = bundleResources.appendingPathComponent(name)
                guard FileManager.default.fileExists(atPath: source.path) else {
                    throw BinaryManagerError.missing(name)
                }
                let expected = name == "yt-dlp" ? manifest.ytdlp.sha256 : manifest.ffmpeg.sha256
                let target = destination.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: target.path),
                   (try? verify(at: target, expectedSHA256: expected)) != nil
                {
                    continue
                }
                // Copy to a temp sibling and atomically swap so a partially-copied
                // binary is never observable by another process.
                let staging = destination.appendingPathComponent(".\(name).\(UUID().uuidString).tmp")
                if FileManager.default.fileExists(atPath: staging.path) {
                    try FileManager.default.removeItem(at: staging)
                }
                try FileManager.default.copyItem(at: source, to: staging)
                try verify(at: staging, expectedSHA256: expected)
                try verifyExecutable(at: staging)
                try verifyArchitectures(at: staging, required: ["arm64", "x86_64"])
                _ = try FileManager.default.replaceItemAt(target, withItemAt: staging)
            }

            let sharedManifest = destination.appendingPathComponent(manifestFileName)
            if FileManager.default.fileExists(atPath: sharedManifest.path) {
                try FileManager.default.removeItem(at: sharedManifest)
            }
            try FileManager.default.copyItem(at: manifestURL, to: sharedManifest)
        }
    }

    /// Resolves the wrapper app's Resources directory when running as an embedded login item.
    public static func wrapperAppResourcesURL() -> URL? {
        let loginItemContents = Bundle.main.bundleURL
        let resources = loginItemContents
            .deletingLastPathComponent() // LoginItems
            .deletingLastPathComponent() // Library
            .deletingLastPathComponent() // Contents
            .appendingPathComponent("Resources", isDirectory: true)
        guard FileManager.default.fileExists(atPath: resources.path) else { return nil }
        return resources
    }

    /// Picks the first candidate Resources directory that actually ships the
    /// downloader manifest. The DownloadDaemon login item has its own (binary-free)
    /// `Resources/`, so `Bundle.main.resourceURL` alone is not a valid seed source —
    /// the wrapper app's Resources must be preferred when it carries the manifest.
    public static func seedResourcesURL() -> URL? {
        let candidates = [Bundle.main.resourceURL, wrapperAppResourcesURL()].compactMap { $0 }
        return candidates.first {
            FileManager.default.fileExists(atPath: $0.appendingPathComponent(manifestFileName).path)
        }
    }

    public static func installSharedBinariesFromBundleIfNeeded() throws {
        // Already seeded (e.g. prior session) — usable even if no bundle source ships binaries.
        if sharedBinariesVerified() { return }
        guard let resources = seedResourcesURL() else {
            throw BinaryManagerError.missingManifest
        }
        try installSharedBinariesIfNeeded(bundleResources: resources)
    }

    /// Runs `body` while holding an exclusive advisory lock on a sentinel file in
    /// `directory`, so concurrent installs across processes do not interleave.
    private static func withInstallLock<T>(in directory: URL, _ body: () throws -> T) throws -> T {
        let lockURL = directory.appendingPathComponent(".install.lock")
        if !FileManager.default.fileExists(atPath: lockURL.path) {
            FileManager.default.createFile(atPath: lockURL.path, contents: nil)
        }
        let fd = open(lockURL.path, O_RDONLY)
        guard fd >= 0 else { return try body() }
        defer { close(fd) }
        flock(fd, LOCK_EX)
        defer { flock(fd, LOCK_UN) }
        return try body()
    }

    public init(
        bundleResources: URL,
        updateRoot: URL = AppGroup.containerURL().appendingPathComponent("downloader-updates")
    ) {
        self.bundleResources = bundleResources
        self.updateRoot = updateRoot
        try? FileManager.default.createDirectory(at: updateRoot, withIntermediateDirectories: true)
    }

    public func ytdlpPath() throws -> URL {
        try preferredPath(name: "yt-dlp")
    }

    public func ffmpegPath() throws -> URL {
        try preferredPath(name: "ffmpeg")
    }

    private func preferredPath(name: String) throws -> URL {
        let updated = updateRoot.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: updated.path) {
            let manifestURL = updateRoot.appendingPathComponent("\(name).manifest.json")
            let signedURL = updateRoot.appendingPathComponent("\(name).manifest.sig")
            if let publicKey = try? DownloaderUpdate.embeddedPublicKey(),
               let payload = try? Data(contentsOf: manifestURL),
               let sig = try? Data(contentsOf: signedURL),
               let manifest = try? DownloaderUpdate.verify(
                   signed: .init(payload: payload, signature: sig), publicKey: publicKey
               ),
               manifest.tool == name,
               (try? Self.verify(at: updated, expectedSHA256: manifest.sha256)) != nil
            {
                try Self.verifyExecutable(at: updated)
                try Self.verifyArchitectures(at: updated, required: ["arm64", "x86_64"])
                return updated
            }
            log.warning("Ignoring unverified updated binary at \(updated.path)")
        }
        let shared = Self.sharedBinariesDirectory().appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: shared.path) {
            let manifestURL = Self.sharedBinariesDirectory().appendingPathComponent(Self.manifestFileName)
            if FileManager.default.fileExists(atPath: manifestURL.path),
               let manifest = try? JSONDecoder().decode(BinaryManifest.self, from: Data(contentsOf: manifestURL))
            {
                let expected = name == "yt-dlp" ? manifest.ytdlp.sha256 : manifest.ffmpeg.sha256
                if (try? Self.verify(at: shared, expectedSHA256: expected)) != nil {
                    try Self.verifyExecutable(at: shared)
                    try Self.verifyArchitectures(at: shared, required: ["arm64", "x86_64"])
                    return shared
                }
            }
        }
        let bundled = bundleResources.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: bundled.path) else {
            throw BinaryManagerError.missing(name)
        }
        let manifestURL = bundleResources.appendingPathComponent("downloader-manifest.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw BinaryManagerError.missingManifest
        }
        let manifest = try JSONDecoder().decode(BinaryManifest.self, from: Data(contentsOf: manifestURL))
        let expected = name == "yt-dlp" ? manifest.ytdlp.sha256 : manifest.ffmpeg.sha256
        try Self.verify(at: bundled, expectedSHA256: expected)
        try Self.verifyExecutable(at: bundled)
        try Self.verifyArchitectures(at: bundled, required: ["arm64", "x86_64"])
        return bundled
    }

    public static func verify(at url: URL, expectedSHA256: String) throws {
        let data = try Data(contentsOf: url)
        let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard actual.lowercased() == expectedSHA256.lowercased() else {
            throw BinaryManagerError.hashMismatch(actual)
        }
    }

    public static func verifyExecutable(at url: URL) throws {
        guard FileManager.default.isExecutableFile(atPath: url.path) else {
            throw BinaryManagerError.notExecutable
        }
    }

    public static func verifyArchitectures(at url: URL, required: Set<String>) throws {
        try verifyArchitecturesImpl(at: url, required: required)
    }

    private static func verifyArchitecturesImpl(at url: URL, required: Set<String>) throws {
        let p = Process()
        let pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/lipo")
        p.arguments = ["-archs", url.path]
        p.standardOutput = pipe
        p.standardError = Pipe()  // suppress stderr; errors surfaced via exit status
        // Use DispatchSemaphore instead of waitUntilExit() to avoid pumping a CFRunLoop
        // on a background thread. waitUntilExit() calls CFRunLoopRun(), which triggers
        // UC framework run-loop observers that crash at a null address on background threads.
        let sem = DispatchSemaphore(value: 0)
        p.terminationHandler = { _ in sem.signal() }
        try p.run()
        sem.wait()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let found = Set(out.split(whereSeparator: \.isWhitespace).map(String.init))
        for arch in required where !found.contains(arch) {
            throw BinaryManagerError.missingArchitecture(arch)
        }
    }
}
