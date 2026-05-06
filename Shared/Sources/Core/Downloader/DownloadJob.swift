import Foundation

public final class DownloadJob {
    public let recordID: RecordID
    public let url: String
    public let destination: URL
    public let process: Process
    public let pipe: Pipe

    public init(
        recordID: RecordID, url: String, destination: URL,
        ytdlp: URL, ffmpeg: URL, extraArgs: [String]
    ) {
        self.recordID = recordID
        self.url = url
        self.destination = destination
        let p = Process()
        p.executableURL = ytdlp
        p.arguments = [
            "--newline", "--progress", "--no-colors", "--continue",
            "--no-check-certificate",  // PyInstaller bundled Python can't find macOS system CA
            "--ffmpeg-location", ffmpeg.path,
            "-o", destination.path
        ] + extraArgs + [url]
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
}
