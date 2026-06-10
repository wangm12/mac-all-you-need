import Foundation

public final class DownloadJob {
    public let recordID: RecordID
    public let url: String
    public let destination: URL
    public let collectionID: String?
    public let collectionIndex: Int?
    public let enqueuedAt: Date
    public let process: Process
    public let pipe: Pipe

    public init(
        recordID: RecordID,
        url: String,
        destination: URL,
        ytdlp: URL,
        ffmpeg: URL,
        extraArgs: [String] = [],
        collectionID: String? = nil,
        collectionIndex: Int? = nil,
        enqueuedAt: Date = Date()
    ) {
        self.recordID = recordID
        self.url = url
        self.destination = destination
        self.collectionID = collectionID
        self.collectionIndex = collectionIndex
        self.enqueuedAt = enqueuedAt
        let p = Process()
        p.executableURL = ytdlp
        let tempDir = DownloadDestinationBuilder.ytdlpTempDirectory()
        var args: [String] = [
            "--newline", "--progress", "--no-colors", "--continue",
            "--no-check-certificate",
            "--concurrent-fragments", "4",
            "--ffmpeg-location", ffmpeg.path,
            "--paths", "temp:\(tempDir.path)",
            "-o", destination.path
        ]
        // Provide Node.js runtime for yt-dlp 2026+ JavaScript extraction
        if let nodePath = Self.findNode() {
            args += ["--js-runtime", "node:\(nodePath)"]
        }
        p.arguments = args + extraArgs + [url]
        var env = ProcessInfo.processInfo.environment
        env["SSL_CERT_FILE"] = "/etc/ssl/cert.pem"
        env["REQUESTS_CA_BUNDLE"] = "/etc/ssl/cert.pem"
        p.environment = env
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        process = p
        self.pipe = pipe
    }

    public func pause() {
        // SIGSTOP only pauses yt-dlp, not its ffmpeg subprocess (used for HLS merging).
        // Use SIGTERM instead — yt-dlp writes partial files that --continue resumes from.
        cancel()
    }

    public func resume() {
        // No-op: resuming is handled by re-enqueueing with --continue via DownloadCoordinator.resumeDownload
    }

    public func cancel() {
        guard process.isRunning else { return }
        kill(process.processIdentifier, SIGTERM)
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) { [process] in
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
    }

    /// Find Node.js for yt-dlp's JavaScript extraction (required in yt-dlp 2026+)
    private static func findNode() -> String? {
        let candidates = [
            "/usr/local/bin/node",
            "/opt/homebrew/bin/node",
            "/usr/bin/node"
        ]
        // Also check nvm path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let nvmNode = "\(home)/.nvm/versions/node"
        if let versions = try? FileManager.default.contentsOfDirectory(atPath: nvmNode),
           let latest = versions.sorted().last
        {
            let nvmPath = "\(nvmNode)/\(latest)/bin/node"
            if FileManager.default.isExecutableFile(atPath: nvmPath) { return nvmPath }
        }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}
