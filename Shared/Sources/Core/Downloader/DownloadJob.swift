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
            "--no-check-certificate", // PyInstaller bundle can't find macOS system CA
            "--ffmpeg-location", ffmpeg.path,
            "-o", destination.path
        ] + extraArgs + [url]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        process = p
        self.pipe = pipe
    }

    public func pause() {
        if process.isRunning { kill(process.processIdentifier, SIGSTOP) }
    }

    public func resume() {
        if process.isRunning { kill(process.processIdentifier, SIGCONT) }
    }

    public func cancel() {
        guard process.isRunning else { return }
        kill(process.processIdentifier, SIGTERM)
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) { [process] in
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
    }
}
