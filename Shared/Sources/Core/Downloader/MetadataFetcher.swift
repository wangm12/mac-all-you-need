import Foundation

public struct VideoMetadata: Sendable, Equatable {
    public let title: String
    public let channelName: String
    public let durationSeconds: Int
    public let thumbnailURL: String
    public let availableHeights: [Int]

    public init(
        title: String,
        channelName: String,
        durationSeconds: Int,
        thumbnailURL: String,
        availableHeights: [Int] = []
    ) {
        self.title = title
        self.channelName = channelName
        self.durationSeconds = durationSeconds
        self.thumbnailURL = thumbnailURL
        self.availableHeights = availableHeights
    }

    // Merges richer data from a subsequent fetch (keeps non-empty fields, merges heights).
    public func merging(_ other: VideoMetadata) -> VideoMetadata {
        VideoMetadata(
            title: other.title.isEmpty ? title : other.title,
            channelName: other.channelName.isEmpty ? channelName : other.channelName,
            durationSeconds: other.durationSeconds > 0 ? other.durationSeconds : durationSeconds,
            thumbnailURL: other.thumbnailURL.isEmpty ? thumbnailURL : other.thumbnailURL,
            availableHeights: other.availableHeights.isEmpty ? availableHeights : other.availableHeights
        )
    }
}

public enum MetadataFetcher {

    // Fast oEmbed fetch for YouTube URLs — returns in ~100ms with no yt-dlp.
    // Returns nil for non-YouTube URLs or on any error.
    public static func fetchOEmbed(url: String) async -> VideoMetadata? {
        guard isYouTubeURL(url) else { return nil }
        guard let encoded = url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let oembedURL = URL(string: "https://www.youtube.com/oembed?url=\(encoded)&format=json")
        else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(from: oembedURL)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return nil }
            let title = json["title"] as? String ?? ""
            let channel = json["author_name"] as? String ?? ""
            let thumbnail = json["thumbnail_url"] as? String ?? ""
            return VideoMetadata(
                title: title,
                channelName: channel,
                durationSeconds: 0,
                thumbnailURL: thumbnail,
                availableHeights: []
            )
        } catch {
            return nil
        }
    }

    // Full fetch via yt-dlp --dump-json. Returns title, channel, duration,
    // thumbnail, and the actual available video heights for this URL.
    public static func fetch(
        url: String,
        ytdlp: URL,
        cookieFile: URL? = nil,
        timeoutSeconds: TimeInterval = 25
    ) async -> VideoMetadata? {
        await Task.detached(priority: .utility) {
            runYTDLPJSONFetch(url: url, ytdlp: ytdlp, cookieFile: cookieFile, timeoutSeconds: timeoutSeconds)
        }.value
    }

    /// Shorter timeout for the format picker — exact heights are optional.
    public static func fetchFormatHeights(
        url: String,
        ytdlp: URL,
        cookieFile: URL? = nil
    ) async -> VideoMetadata? {
        await fetch(url: url, ytdlp: ytdlp, cookieFile: cookieFile, timeoutSeconds: 8)
    }

    private static func runYTDLPJSONFetch(
        url: String,
        ytdlp: URL,
        cookieFile: URL?,
        timeoutSeconds: TimeInterval
    ) -> VideoMetadata? {
        let p = Process()
        p.executableURL = ytdlp
        var args = [
            "--no-download",
            "--no-check-certificate",
            "--dump-json",
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
        DispatchQueue.global().asyncAfter(deadline: .now() + timeoutSeconds) {
            if p.isRunning { p.terminate() }
        }
        let semaphore = DispatchSemaphore(value: 0)
        p.terminationHandler = { _ in semaphore.signal() }
        semaphore.wait()
        guard p.terminationStatus == 0 else { return nil }
        let raw = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let json = try? JSONSerialization.jsonObject(with: raw) as? [String: Any] else {
            return nil
        }
        let title = json["title"] as? String ?? ""
        let channel = (json["uploader"] as? String)
            ?? (json["channel"] as? String)
            ?? (json["creator"] as? String) ?? ""
        let duration = Int(json["duration"] as? Double ?? 0)
        let thumbnail = json["thumbnail"] as? String ?? ""
        let heights = parseAvailableHeights(from: json)
        return VideoMetadata(
            title: title,
            channelName: channel,
            durationSeconds: duration,
            thumbnailURL: thumbnail,
            availableHeights: heights
        )
    }

    private static func isYouTubeURL(_ url: String) -> Bool {
        guard let host = URL(string: url)?.host?.lowercased() else { return false }
        return host == "youtube.com" || host == "www.youtube.com"
            || host == "youtu.be" || host == "m.youtube.com"
            || host == "music.youtube.com"
    }

    // Extract unique video heights from the formats array, sorted descending.
    private static func parseAvailableHeights(from json: [String: Any]) -> [Int] {
        guard let formats = json["formats"] as? [[String: Any]] else { return [] }
        var heights = Set<Int>()
        for fmt in formats {
            let vcodec = fmt["vcodec"] as? String ?? ""
            guard vcodec != "none", !vcodec.isEmpty else { continue }
            if let h = fmt["height"] as? Int, h > 0 {
                heights.insert(h)
            }
        }
        return heights.sorted().reversed().map { $0 }
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

