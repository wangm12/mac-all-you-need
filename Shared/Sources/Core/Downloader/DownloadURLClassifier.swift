import Foundation

public enum DownloadURLRoute: Equatable, Sendable {
    case douyinProfile(String)
    case collection(String)
    case single(String)
    case multiURL([String])
}

public enum DownloadURLClassifier {
    public static func route(for rawInput: String) -> DownloadURLRoute? {
        let trimmed = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let lines = splitMultiURL(trimmed)
        if lines.count > 1 {
            return .multiURL(lines)
        }

        let url = lines[0]
        if isDouyinProfileHomeURL(url) {
            return .douyinProfile(url)
        }
        if shouldOpenCollectionPicker(url) {
            return .collection(url)
        }
        return .single(url)
    }

    public static func splitMultiURL(_ text: String) -> [String] {
        text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    public static func isDouyinProfileHomeURL(_ url: String) -> Bool {
        let raw = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return false }
        guard let parsed = normalizedURL(raw) else {
            return matches(raw, pattern: #"(?:^|\/\/)www\.douyin\.com\/user\/|(?:^|\/)douyin\.com\/user\/"#)
        }
        let host = parsed.host?.lowercased() ?? ""
        guard host == "douyin.com" || host.hasSuffix(".douyin.com") else { return false }
        return parsed.path.range(of: "/user/", options: .caseInsensitive) != nil
    }

    public static func isPlaylistURL(_ url: String) -> Bool {
        matches(url, pattern: #"[?&]list="#)
            || matches(url, pattern: #"youtube\.com\/(@[\w-]+|channel\/[\w-]+|c\/[\w-]+|user\/[\w-]+)(\/|$)"#)
    }

    public static func isBilibiliSpaceURL(_ url: String) -> Bool {
        matches(url, pattern: #"space\.bilibili\.com|bilibili\.com\/space\/"#)
    }

    public static func isBilibiliAnthologyCandidate(_ url: String) -> Bool {
        guard matches(url, pattern: #"bilibili\.com\/video\/"#) else { return false }
        guard let components = URLComponents(string: url) else { return false }
        return components.queryItems?.contains(where: { $0.name == "p" }) != true
    }

    public static func shouldOpenCollectionPicker(_ url: String) -> Bool {
        isPlaylistURL(url) || isBilibiliSpaceURL(url) || isBilibiliAnthologyCandidate(url)
    }

    public static func collectionPickerLabel(for url: String) -> String {
        if isBilibiliSpaceURL(url) || isBilibiliAnthologyCandidate(url) { return "Bilibili" }
        if isPlaylistURL(url) { return "YouTube" }
        return "Playlist"
    }

    public static func isBilibiliVideoURL(_ url: String) -> Bool {
        matches(url, pattern: #"bilibili\.com\/video\/|b23\.tv"#)
    }

    /// True for playlist/channel/profile URLs that `URLDetector` may not classify as single videos.
    public static func isDownloadablePasteboardURL(_ url: String) -> Bool {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, normalizedURL(trimmed) != nil else { return false }
        return isDouyinProfileHomeURL(trimmed)
            || shouldOpenCollectionPicker(trimmed)
            || isBilibiliVideoURL(trimmed)
            || isBilibiliSpaceURL(trimmed)
    }

    /// First bulk/collection URL embedded in clipboard text (multi-line or inline prose).
    public static func firstDownloadableURL(in text: String) -> String? {
        for line in splitMultiURL(text) where isDownloadablePasteboardURL(line) {
            return line
        }
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        for match in detector.matches(in: text, range: range) {
            guard let url = match.url?.absoluteString, isDownloadablePasteboardURL(url) else { continue }
            return url
        }
        return nil
    }

    private static func normalizedURL(_ raw: String) -> URL? {
        let withProto = raw.lowercased().hasPrefix("http://") || raw.lowercased().hasPrefix("https://")
            ? raw
            : "https://\(raw)"
        return URL(string: withProto)
    }

    private static func matches(
        _ text: String,
        pattern: String,
        options: NSRegularExpression.Options = []
    ) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return false }
        let range = NSRange(text.startIndex ..< text.endIndex, in: text)
        return regex.firstMatch(in: text, options: [], range: range) != nil
    }
}
