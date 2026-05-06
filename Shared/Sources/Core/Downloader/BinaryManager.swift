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
    public let bundleResources: URL
    public let updateRoot: URL
    private let log = Logging.logger(for: "downloader", category: "binaries")

    public init(
        bundleResources: URL,
        updateRoot: URL = AppGroup.containerURL().appendingPathComponent("downloader-updates")
    ) {
        self.bundleResources = bundleResources
        self.updateRoot = updateRoot
        try? FileManager.default.createDirectory(at: updateRoot, withIntermediateDirectories: true)
    }

    public func ytdlpPath() throws -> URL { try preferredPath(name: "yt-dlp") }
    public func ffmpegPath() throws -> URL { try preferredPath(name: "ffmpeg") }

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
               (try? Self.verify(at: updated, expectedSHA256: manifest.sha256)) != nil {
                try Self.verifyExecutable(at: updated)
                try Self.verifyArchitectures(at: updated, required: ["arm64", "x86_64"])
                return updated
            }
            log.warning("Ignoring unverified updated binary at \(updated.path)")
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
        let p = Process()
        let pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/lipo")
        p.arguments = ["-archs", url.path]
        p.standardOutput = pipe
        try p.run()
        p.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let found = Set(out.split(separator: " ").map(String.init))
        for arch in required where !found.contains(arch) {
            throw BinaryManagerError.missingArchitecture(arch)
        }
    }
}
