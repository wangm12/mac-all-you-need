import Foundation

public struct VideoMetadata: Sendable {
    public let title: String
    public let channelName: String
    public let durationSeconds: Int
    public let thumbnailURL: String
}

public enum MetadataFetcher {
    public static func fetch(url: String, ytdlp: URL) async -> VideoMetadata? {
        await Task.detached(priority: .utility) {
            let p = Process()
            p.executableURL = ytdlp
            // Use --print to get individual fields, separated by a unique delimiter
            p.arguments = [
                "--no-download",
                "--no-check-certificate",
                "--print", "%(title)s",
                "--print", "%(uploader|channel)s",
                "--print", "%(duration)s",
                "--print", "%(thumbnail)s",
                url
            ]
            var env = ProcessInfo.processInfo.environment
            env["SSL_CERT_FILE"] = "/etc/ssl/cert.pem"
            p.environment = env
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = Pipe() // discard stderr
            do {
                try p.run()
            } catch {
                return nil
            }
            // Timeout: kill after 15s if metadata fetch hangs
            DispatchQueue.global().asyncAfter(deadline: .now() + 15) {
                if p.isRunning { p.terminate() }
            }
            p.waitUntilExit()
            guard p.terminationStatus == 0 else { return nil }
            let raw = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let lines = raw.components(separatedBy: "\n").filter { !$0.isEmpty }
            guard lines.count >= 4 else { return nil }
            let duration = Int(lines[2]) ?? 0
            return VideoMetadata(
                title: lines[0],
                channelName: lines[1],
                durationSeconds: duration,
                thumbnailURL: lines[3]
            )
        }.value
    }
}
