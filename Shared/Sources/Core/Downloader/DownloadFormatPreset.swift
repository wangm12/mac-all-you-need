import Foundation

public enum DownloadFormatPreset: String, Sendable, CaseIterable {
    case videoBest
    case video1080
    case video720
    case video360
    case video240
    case video144
    case audio320
    case audio128

    public var displayLabel: String {
        switch self {
        case .videoBest: "Best available"
        case .video1080: "1080p (.mp4)"
        case .video720: "720p (.mp4)"
        case .video360: "360p (.mp4)"
        case .video240: "240p (.mp4)"
        case .video144: "144p (.mp4)"
        case .audio320: "MP3 (320kbps)"
        case .audio128: "MP3 (128kbps)"
        }
    }

    public var isAudio: Bool {
        switch self {
        case .audio320, .audio128: true
        default: false
        }
    }

    public var qualityHeight: Int {
        switch self {
        case .videoBest: Int.max
        case .video1080: 1080
        case .video720: 720
        case .video360: 360
        case .video240: 240
        case .video144: 144
        case .audio320: 320
        case .audio128: 128
        }
    }

    public static func fromDefaultQualitySetting(_ height: Int) -> DownloadFormatPreset {
        switch height {
        case ..<240: .video144
        case 240 ..< 360: .video240
        case 360 ..< 720: .video360
        case 720 ..< 1080: .video720
        default: .video1080
        }
    }

    /// Create a preset for an arbitrary height from the video's available formats.
    public static func forHeight(_ height: Int) -> DownloadFormatPreset {
        switch height {
        case ..<240: .video144
        case 240 ..< 360: .video240
        case 360 ..< 720: .video360
        case 720 ..< 1080: .video720
        case 1080: .video1080
        default: .videoBest
        }
    }

    public func ytdlpArgs() -> [String] {
        switch self {
        case .videoBest:
            ["-f", "bestvideo+bestaudio/best", "--merge-output-format", "mp4"]
        case .video1080, .video720, .video360, .video240, .video144:
            [
                "-f", "bestvideo[height<=\(qualityHeight)]+bestaudio/best[height<=\(qualityHeight)]",
                "--merge-output-format", "mp4"
            ]
        case .audio320:
            ["-f", "bestaudio", "--extract-audio", "--audio-format", "mp3", "--audio-quality", "0"]
        case .audio128:
            ["-f", "bestaudio", "--extract-audio", "--audio-format", "mp3", "--audio-quality", "5"]
        }
    }
}

public enum DownloadDestinationBuilder {
    public static func sanitizeFolderName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Playlist" }
        let invalid = CharacterSet(charactersIn: "/\\:?*\"<>|")
        let cleaned = trimmed.unicodeScalars.map { invalid.contains($0) ? "_" : Character($0) }
        let result = String(cleaned).trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? "Playlist" : String(result.prefix(120))
    }

    public static func outputDirectory(
        collectionTitle: String? = nil,
        useCollectionSubfolder: Bool = true
    ) throws -> URL {
        let configured = AppGroupSettings.defaults.string(forKey: "downloadDirectory") ?? ""
        let base: URL = {
            if !configured.isEmpty {
                return URL(fileURLWithPath: configured, isDirectory: true)
            }
            let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: "/tmp")
            return downloads.appendingPathComponent("MacAllYouNeed", isDirectory: true)
        }()
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)

        if useCollectionSubfolder,
           let collectionTitle,
           !collectionTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            let sub = base.appendingPathComponent(sanitizeFolderName(collectionTitle), isDirectory: true)
            try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
            return sub
        }
        return base
    }

    public static func destinationURL(
        collectionTitle: String? = nil,
        useCollectionSubfolder: Bool = true
    ) throws -> URL {
        let outputDir = try outputDirectory(
            collectionTitle: collectionTitle,
            useCollectionSubfolder: useCollectionSubfolder
        )
        let template = AppGroupSettings.defaults.string(forKey: "downloadOutputTemplate")
            ?? "%(title)s - %(uploader)s.%(ext)s"
        return URL(fileURLWithPath: outputDir.path + "/" + template)
    }

    public static func ytdlpTempDirectory() -> URL {
        let dir = AppGroup.containerURL()
            .appendingPathComponent("tmp/yt-dlp", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
