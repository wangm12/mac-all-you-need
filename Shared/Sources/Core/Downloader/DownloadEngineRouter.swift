import Foundation

public enum DownloadEngineKind: String, Sendable {
    case ytdlp
    case ffmpegDirect
    case douyinDirect
}

public enum DownloadEngineRouter {
    public static func selectEngine(for record: DownloadRecord) -> DownloadEngineKind {
        if record.douyinAwemeID?.isEmpty == false || record.douyinImageURLs?.isEmpty == false {
            return .douyinDirect
        }
        if DouyinDownloadURLPatterns.prefersNativeResolve(url: record.url) {
            return .douyinDirect
        }
        if let mediaType = record.mediaType?.lowercased(), !mediaType.isEmpty {
            if mediaType == "hls" || mediaType.contains("m3u8") {
                return .ytdlp
            }
            let directTypes: Set<String> = [
                "mp4", "webm", "flv", "mov", "m4v", "mkv", "ts",
                "mp3", "m4a", "aac", "wav", "opus", "ogg"
            ]
            if directTypes.contains(mediaType) {
                return .ffmpegDirect
            }
            return .ytdlp
        }
        if record.url.localizedCaseInsensitiveContains("douyin.com") {
            return .douyinDirect
        }
        return .ytdlp
    }
}
