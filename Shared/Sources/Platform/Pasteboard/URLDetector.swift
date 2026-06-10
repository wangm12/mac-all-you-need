import Core
import Foundation

public enum URLDetector {
    private static let videoHostSuffixes: [String] = [
        "youtube.com", "youtu.be",
        "vimeo.com",
        "x.com", "twitter.com",
        "douyin.com", "tiktok.com",
        "twitch.tv",
        "bilibili.com", "b23.tv"
    ]

    private static let shareURLPatterns: [String] = [
        #"https?://v\.douyin\.com/[\w-]+/?"#,
        #"https?://(?:[\w-]+\.)*douyin\.com/[\w/?=&%._-]+"#,
        #"(?:https?://)?v\.douyin\.com/[\w-]+/?"#
    ]

    public static func videoBearingURL(in text: String) -> URL? {
        extractVideoBearingURLs(from: text).first
    }

    /// First downloadable URL in clipboard/share prose (single videos, short links, playlists).
    public static func firstDownloadableURL(in text: String) -> String? {
        allDownloadableURLs(in: text).first
    }

    /// All downloadable URLs embedded in share text or multi-line paste.
    public static func allDownloadableURLs(in text: String) -> [String] {
        var results: [String] = []
        var seen = Set<String>()

        func append(_ raw: String) {
            let normalized = normalizeURLString(raw)
            guard !normalized.isEmpty, seen.insert(normalized).inserted else { return }
            if isDownloadableURL(normalized) {
                results.append(normalized)
            }
        }

        for url in extractVideoBearingURLs(from: text) {
            append(url.absoluteString)
        }

        for match in regexMatches(in: text) {
            append(match)
        }

        for line in DownloadURLClassifier.splitMultiURL(text) where DownloadURLClassifier.isDownloadablePasteboardURL(line) {
            append(line)
        }

        return results
    }

    public static func extractVideoBearingURLs(from text: String) -> [URL] {
        var results: [URL] = []
        var seen = Set<String>()

        func append(_ url: URL) {
            guard let host = url.host?.lowercased(), isVideoHost(host) else { return }
            if seen.insert(url.absoluteString).inserted {
                results.append(url)
            }
        }

        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            let range = NSRange(text.startIndex..., in: text)
            for match in detector.matches(in: text, range: range) {
                if let url = match.url {
                    append(url)
                }
            }
        }

        for raw in regexMatches(in: text) {
            guard let url = URL(string: normalizeURLString(raw)) else { continue }
            append(url)
        }

        return results
    }

    private static func isDownloadableURL(_ url: String) -> Bool {
        if DownloadURLClassifier.isDownloadablePasteboardURL(url) { return true }
        guard let parsed = URL(string: url), let host = parsed.host?.lowercased() else { return false }
        return isVideoHost(host)
    }

    private static func regexMatches(in text: String) -> [String] {
        var matches: [String] = []
        for pattern in shareURLPatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(text.startIndex..., in: text)
            for result in regex.matches(in: text, range: range) {
                guard let swiftRange = Range(result.range, in: text) else { continue }
                let snippet = String(text[swiftRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !snippet.isEmpty {
                    matches.append(snippet)
                }
            }
        }
        return matches
    }

    private static func normalizeURLString(_ raw: String) -> String {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let trailingGlue = CharacterSet.whitespacesAndNewlines
            .union(CharacterSet(charactersIn: "，。！？、；："))
        trimmed = trimmed.trimmingCharacters(in: trailingGlue)
        if trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://") {
            if trimmed.lowercased().contains("douyin.com") {
                return trimmed.replacingOccurrences(of: "http://", with: "https://", options: .caseInsensitive)
            }
            return trimmed
        }
        if trimmed.contains("douyin.com/") || trimmed.contains("b23.tv/") || trimmed.contains("bilibili.com/") {
            let stripped = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return "https://\(stripped)"
        }
        return trimmed
    }

    private static func isVideoHost(_ host: String) -> Bool {
        videoHostSuffixes.contains { suffix in
            host == suffix || host.hasSuffix(".\(suffix)")
        }
    }
}
