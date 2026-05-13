import Foundation

public struct VideoMetadata: Sendable {
    public let title: String
    public let channelName: String
    public let durationSeconds: Int
    public let thumbnailURL: String
}

public enum MetadataFetcher {
    public static func fetch(url: String, ytdlp: URL, cookieFile: URL? = nil) async -> VideoMetadata? {
        await Task.detached(priority: .utility) {
            let p = Process()
            p.executableURL = ytdlp
            var args = [
                "--no-download",
                "--no-check-certificate",
                "--print", "%(title)s",
                "--print", "%(uploader|channel)s",
                "--print", "%(duration)s",
                "--print", "%(thumbnail)s"
            ]
            if let node = findNode() {
                args += ["--js-runtime", "node:\(node)"]
            }
            if let cookieFile {
                args += ["--cookies", cookieFile.path]
            }
            args.append(url)
            p.arguments = args
            var env = ProcessInfo.processInfo.environment
            env["SSL_CERT_FILE"] = "/etc/ssl/cert.pem"
            p.environment = env
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = Pipe()
            do { try p.run() } catch { return nil }
            DispatchQueue.global().asyncAfter(deadline: .now() + 25) {
                if p.isRunning { p.terminate() }
            }
            p.waitUntilExit()
            NSLog("🎬 MetadataFetcher: exit=\(p.terminationStatus) url=\(url)")
            guard p.terminationStatus == 0 else { return nil }
            let raw = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let lines = raw.components(separatedBy: "\n").filter { !$0.isEmpty }
            NSLog("🎬 MetadataFetcher: lines=\(lines)")
            guard lines.count >= 4 else { return nil }
            return VideoMetadata(
                title: lines[0],
                channelName: lines[1],
                durationSeconds: Int(lines[2]) ?? 0,
                thumbnailURL: lines[3]
            )
        }.value
    }

    private static func findNode() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let nvmNode = "\(home)/.nvm/versions/node"
        if let versions = try? FileManager.default.contentsOfDirectory(atPath: nvmNode),
           let latest = versions.sorted().last
        {
            let path = "\(nvmNode)/\(latest)/bin/node"
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return ["/usr/local/bin/node", "/opt/homebrew/bin/node"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}

