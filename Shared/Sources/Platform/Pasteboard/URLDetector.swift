import Foundation

public enum URLDetector {
    private static let videoHosts: Set<String> = [
        "youtube.com", "youtu.be", "www.youtube.com",
        "vimeo.com", "player.vimeo.com",
        "x.com", "twitter.com",
        "douyin.com", "tiktok.com",
        "twitch.tv",
    ]

    public static func videoBearingURL(in text: String) -> URL? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let matches = detector?.matches(in: text, range: NSRange(text.startIndex..., in: text)) ?? []
        for m in matches {
            if let url = m.url, let host = url.host?.lowercased(), videoHosts.contains(host) {
                return url
            }
        }
        return nil
    }
}
