import Foundation

public enum PlaylistEntryLister {
    public static let maxBulkItems = 2000

    public static func list(
        url: String,
        ytdlp: URL,
        cookieFile: URL? = nil
    ) async throws -> PlaylistListResult {
        try await Task.detached(priority: .utility) {
            try listSync(url: url, ytdlp: ytdlp, cookieFile: cookieFile)
        }.value
    }

    static func listSync(
        url: String,
        ytdlp: URL,
        cookieFile: URL? = nil
    ) throws -> PlaylistListResult {
        let p = Process()
        p.executableURL = ytdlp
        var args = [
            "--dump-json",
            "--flat-playlist",
            "--no-download",
            "--no-warnings",
            "--no-check-certificate"
        ]
        if let node = YtdlpProcessHelpers.findNode() {
            args += ["--js-runtime", "node:\(node)"]
        }
        if let cookieFile {
            args += ["--cookies", cookieFile.path]
        }
        args.append(url)

        var env = ProcessInfo.processInfo.environment
        env["SSL_CERT_FILE"] = "/etc/ssl/cert.pem"
        env["REQUESTS_CA_BUNDLE"] = "/etc/ssl/cert.pem"
        p.environment = env
        p.arguments = args

        let outPipe = Pipe()
        let errPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = errPipe
        try p.run()
        p.waitUntilExit()

        let stdout = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        guard p.terminationStatus == 0 else {
            throw PlaylistListError.ytdlpFailed(code: p.terminationStatus, message: stderr.isEmpty ? stdout : stderr)
        }

        var items: [PlaylistEntryRow] = []
        var metaTitle: String?
        var metaChannel: String?

        for line in stdout.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }

            let type = json["_type"] as? String
            if type == "playlist" {
                if let title = json["title"] as? String, !title.isEmpty {
                    metaTitle = title
                }
                continue
            }

            if type == "video" || type == "url" || json["id"] != nil {
                collectMeta(from: json, title: &metaTitle, channel: &metaChannel)
                items.append(row(from: json, playlistTitle: metaTitle, playlistChannel: metaChannel))
            }
        }

        guard !items.isEmpty else {
            throw PlaylistListError.noEntries
        }

        let collectionTitle = metaTitle?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? items.first?.title
            ?? "Playlist"
        let channel = metaChannel?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? items.first(where: { !$0.channel.isEmpty })?.channel
            ?? ""

        return PlaylistListResult(
            items: items,
            collectionTitle: collectionTitle,
            channel: channel,
            sourceURL: url
        )
    }

    static func row(
        from json: [String: Any],
        playlistTitle: String?,
        playlistChannel: String?
    ) -> PlaylistEntryRow {
        let id = String(describing: json["id"] ?? "")
        let title = entryDisplayTitle(json: json, playlistTitle: playlistTitle)
        let channel = String(describing: json["channel"]
            ?? json["uploader"]
            ?? json["playlist_uploader"]
            ?? playlistChannel
            ?? "")
        let thumb = thumbnailURL(from: json)
        let duration = (json["duration"] as? NSNumber)?.intValue ?? 0
        let pageURL = String(describing: json["webpage_url"] ?? json["url"] ?? "")
        let index = (json["playlist_index"] as? NSNumber)?.intValue

        return PlaylistEntryRow(
            id: id,
            title: title,
            channel: channel,
            thumbnail: thumb,
            durationSeconds: duration,
            pageURL: pageURL,
            playlistIndex: index
        )
    }

    static func entryDisplayTitle(json: [String: Any], playlistTitle: String?) -> String {
        let raw = (json["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !raw.isEmpty, raw != "Unknown" { return raw }

        let idx = (json["playlist_index"] as? NSNumber)?.intValue
        let series = (json["playlist_title"] as? String ?? playlistTitle ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !series.isEmpty, let idx {
            return "\(series) · p\(String(format: "%02d", idx))"
        }
        if let idx { return "Part \(idx)" }

        let id = (json["id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !id.isEmpty { return id }
        return "Untitled"
    }

    static func collectMeta(
        from json: [String: Any],
        title: inout String?,
        channel: inout String?
    ) {
        if title?.isEmpty != false,
           let t = json["playlist_title"] as? String, !t.isEmpty
        {
            title = t
        }
        if channel?.isEmpty != false {
            let c = json["playlist_uploader"] as? String
                ?? json["uploader"] as? String
                ?? json["channel"] as? String
            if let c, !c.isEmpty { channel = c }
        }
    }

    static func thumbnailURL(from json: [String: Any]) -> String {
        if let thumbs = json["thumbnails"] as? [[String: Any]],
           let first = thumbs.first?["url"] as? String
        {
            return first
        }
        return (json["thumbnail"] as? String) ?? ""
    }
}

public enum PlaylistListError: LocalizedError {
    case noEntries
    case ytdlpFailed(code: Int32, message: String)
    case tooManyItems(count: Int)

    public var errorDescription: String? {
        switch self {
        case .noEntries:
            "No videos found in this playlist or channel"
        case let .ytdlpFailed(_, message):
            message.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                ?? "yt-dlp list failed"
        case let .tooManyItems(count):
            "Too many items (\(count)). Maximum is \(PlaylistEntryLister.maxBulkItems)."
        }
    }
}

enum YtdlpProcessHelpers {
    static func findNode() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let nvmNode = "\(home)/.nvm/versions/node"
        if let versions = try? FileManager.default.contentsOfDirectory(atPath: nvmNode),
           let latest = versions.sorted().last
        {
            let path = "\(nvmNode)/\(latest)/bin/node"
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return ["/usr/local/bin/node", "/opt/homebrew/bin/node", "/usr/bin/node"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
