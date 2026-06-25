import Core
import Foundation
import os

struct DouyinResolvedVideo: Sendable, Equatable {
    let awemeId: String
    let title: String
    let author: String
    let directURL: String
    let thumbnailURL: String?
    let downloadHeaders: [String: String]
}

enum DouyinVideoClientError: Error, LocalizedError {
    case unsupportedURL
    case detailUnavailable
    case noPlayableURL

    var errorDescription: String? {
        switch self {
        case .unsupportedURL:
            "Could not resolve this Douyin link."
        case .detailUnavailable:
            "Douyin did not return video details. Open douyin.com in your browser, sync cookies, then retry."
        case .noPlayableURL:
            "No playable video URL was found for this Douyin post."
        }
    }
}

/// Native Douyin single-video resolver using signed web APIs (reference: douyin-downloader).
enum DouyinVideoClient {
    private static let log = Logger(subsystem: "com.macallyouneed.app", category: "douyin-video")
    private static let galleryAwemeTypes: Set<Int> = [2, 68, 150]
    private static let detailAIDs = ["6383", "1128"]

    static func extractAwemeID(from rawURL: String) -> String? {
        let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let patterns = [
            #"/video/(\d{10,})"#,
            #"/note/(\d{10,})"#,
            #"modal_id=(\d{10,})"#,
            #"aweme_id=(\d{10,})"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex ..< trimmed.endIndex, in: trimmed)),
                  match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: trimmed)
            else { continue }
            return String(trimmed[range])
        }
        return nil
    }

    static func resolveCanonicalPageURL(_ rawURL: String, cookieFile: URL? = nil) async -> String? {
        if let awemeId = extractAwemeID(from: rawURL) {
            return "https://www.douyin.com/video/\(awemeId)"
        }
        guard let url = normalizedURL(rawURL) else { return nil }
        guard let host = url.host?.lowercased(),
              host.contains("douyin.com") || host.contains("iesdouyin.com")
        else { return nil }

        let cookieMap = DouyinAPISupport.cookieMap(from: cookieFile)
        let msToken = DouyinAPISupport.resolveMsToken(cookieMap: cookieMap)
        let cookieHeader = DouyinAPISupport.cookieHeader(cookieMap: cookieMap, msToken: msToken)

        if let resolved = await followDouyinShortLink(startingURL: url, cookieHeader: cookieHeader) {
            return resolved
        }
        log.warning("short-link resolve failed for \(rawURL, privacy: .public)")
        return nil
    }

    private static func followDouyinShortLink(startingURL: URL, cookieHeader: String?) async -> String? {
        var current = startingURL
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        let session = URLSession(configuration: config, delegate: RedirectBlocker.shared, delegateQueue: nil)

        for _ in 0 ..< 8 {
            var request = URLRequest(url: current)
            request.httpMethod = "GET"
            request.setValue(DouyinAPISupport.apiUserAgent, forHTTPHeaderField: "User-Agent")
            request.setValue(DouyinAPISupport.referer, forHTTPHeaderField: "Referer")
            if let cookieHeader {
                request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
            }

            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await session.data(for: request)
            } catch {
                return nil
            }
            guard let http = response as? HTTPURLResponse else { return nil }
            let currentURL = http.url ?? current

            if let awemeId = extractAwemeID(from: currentURL.absoluteString) {
                return "https://www.douyin.com/video/\(awemeId)"
            }

            if (300 ... 399).contains(http.statusCode),
               let location = http.value(forHTTPHeaderField: "Location"),
               let next = URL(string: location, relativeTo: currentURL)?.absoluteURL
            {
                current = next
                continue
            }

            if let html = String(data: data, encoding: .utf8),
               let awemeId = extractAwemeID(from: html)
            {
                return "https://www.douyin.com/video/\(awemeId)"
            }
            return currentURL.absoluteString
        }
        return nil
    }

    static func resolve(url rawURL: String, cookieFile: URL?) async throws -> DouyinResolvedVideo {
        let pageURL = await resolveCanonicalPageURL(rawURL, cookieFile: cookieFile) ?? rawURL
        guard let awemeId = extractAwemeID(from: pageURL) else {
            throw DouyinVideoClientError.unsupportedURL
        }

        let cookieMap = DouyinAPISupport.cookieMap(from: cookieFile)
        let msToken = DouyinAPISupport.resolveMsToken(cookieMap: cookieMap)
        let detail = try await fetchVideoDetail(awemeId: awemeId, cookieMap: cookieMap, msToken: msToken)
        if isGallery(detail), !hasVideoSource(detail) {
            throw DouyinVideoClientError.noPlayableURL
        }

        guard let playable = buildPlayableURL(from: detail, msToken: msToken) else {
            throw DouyinVideoClientError.noPlayableURL
        }

        let meta = metadata(from: detail)
        return DouyinResolvedVideo(
            awemeId: awemeId,
            title: meta.title,
            author: meta.channelName,
            directURL: playable.url,
            thumbnailURL: meta.thumbnailURL.nilIfEmpty,
            downloadHeaders: playable.headers
        )
    }

    /// Format-picker metadata via signed Douyin API (avoids yt-dlp hang on short links).
    static func fetchMetadata(url rawURL: String, cookieFile: URL?) async -> VideoMetadata? {
        let pageURL = await resolveCanonicalPageURL(rawURL, cookieFile: cookieFile) ?? rawURL
        guard let awemeId = extractAwemeID(from: pageURL) else { return nil }
        let cookieMap = DouyinAPISupport.cookieMap(from: cookieFile)
        let msToken = DouyinAPISupport.resolveMsToken(cookieMap: cookieMap)
        guard let detail = try? await fetchVideoDetail(
            awemeId: awemeId,
            cookieMap: cookieMap,
            msToken: msToken
        ) else {
            return nil
        }
        return metadata(from: detail)
    }

    private static func metadata(from detail: [String: Any]) -> VideoMetadata {
        let awemeId = String(describing: detail["aweme_id"] ?? detail["awemeId"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let title = (detail["desc"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let author = ((detail["author"] as? [String: Any])?["nickname"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let displayTitle: String = if title.isEmpty {
            awemeId.isEmpty ? "Douyin video" : "Douyin post \(awemeId)"
        } else {
            title
        }
        return VideoMetadata(
            title: displayTitle,
            channelName: author,
            durationSeconds: extractDuration(from: detail),
            thumbnailURL: extractThumbnail(from: detail) ?? "",
            availableHeights: extractAvailableHeights(from: detail)
        )
    }

    // MARK: - API

    private static func fetchVideoDetail(
        awemeId: String,
        cookieMap: [String: String],
        msToken: String
    ) async throws -> [String: Any] {
        let retryDelays: [TimeInterval] = [1, 2, 5]

        for aid in detailAIDs {
            var lastRoot: [String: Any] = [:]
            for attempt in 0 ..< 3 {
                let query = DouyinAPISupport.defaultWebQueryItems(
                    msToken: msToken,
                    extra: [
                        .init(name: "aweme_id", value: awemeId),
                        .init(name: "aid", value: aid)
                    ]
                )
                guard let requestURL = DouyinAPISupport.signedURLWithABogus(
                    path: "/aweme/v1/web/aweme/detail/",
                    queryItems: query
                ) else { throw DouyinVideoClientError.detailUnavailable }

                var request = URLRequest(url: requestURL)
                request.setValue(DouyinAPISupport.apiUserAgent, forHTTPHeaderField: "User-Agent")
                request.setValue(DouyinAPISupport.referer, forHTTPHeaderField: "Referer")
                request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
                request.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
                if let cookieHeader = DouyinAPISupport.cookieHeader(cookieMap: cookieMap, msToken: msToken) {
                    request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
                }

                let data: Data
                do {
                    (data, _) = try await URLSession.shared.data(for: request)
                } catch {
                    if attempt < 2 {
                        try await Task.sleep(nanoseconds: UInt64(retryDelays[attempt] * 1_000_000_000))
                        continue
                    }
                    throw DouyinVideoClientError.detailUnavailable
                }

                guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    if attempt < 2 {
                        try await Task.sleep(nanoseconds: UInt64(retryDelays[attempt] * 1_000_000_000))
                        continue
                    }
                    throw DouyinVideoClientError.detailUnavailable
                }
                lastRoot = root

                if let detail = root["aweme_detail"] as? [String: Any], !detail.isEmpty {
                    return detail
                }

                let filterInfo = root["filter_detail"] as? [String: Any]
                if let reason = filterInfo?["filter_reason"] as? String, !reason.isEmpty {
                    log.info("detail filtered aid=\(aid, privacy: .public) reason=\(reason, privacy: .public)")
                    break
                }

                let statusCode = (root["status_code"] as? Int) ?? 0
                let isAntiBot = data.isEmpty || (statusCode == 0 && root["aweme_detail"] == nil)
                if isAntiBot, attempt < 2 {
                    try await Task.sleep(nanoseconds: UInt64(retryDelays[attempt] * 1_000_000_000))
                    continue
                }
                break
            }

            if let detail = lastRoot["aweme_detail"] as? [String: Any], !detail.isEmpty {
                return detail
            }
        }

        throw DouyinVideoClientError.detailUnavailable
    }

    // MARK: - Play URL selection (reference: downloader_base._build_no_watermark_url)

    private static func buildPlayableURL(
        from detail: [String: Any],
        msToken: String?
    ) -> (url: String, headers: [String: String])? {
        guard let video = detail["video"] as? [String: Any] else { return nil }
        let playAddr = pickPreferredPlayAddr(from: video) ?? [:]
        var urlCandidates = (playAddr["url_list"] as? [Any])?
            .compactMap { value -> String? in
                let url = String(describing: value).trimmingCharacters(in: .whitespacesAndNewlines)
                return url.lowercased().hasPrefix("http") ? url : nil
            } ?? []
        urlCandidates.sort { lhs, rhs in
            let lhsWM = lhs.contains("watermark=1") ? 1 : 0
            let rhsWM = rhs.contains("watermark=1") ? 1 : 0
            if lhsWM != rhsWM { return lhsWM < rhsWM }
            let lhsCDN = lhs.contains("douyinvod.com") ? 0 : 1
            let rhsCDN = rhs.contains("douyinvod.com") ? 0 : 1
            return lhsCDN < rhsCDN
        }

        var fallbackCDN: (String, [String: String])?
        var watermarked: (String, [String: String])?

        for candidate in urlCandidates {
            let headers = downloadHeaders()
            let isWatermarked = candidate.contains("watermark=1")
            if let host = URL(string: candidate)?.host?.lowercased(), host.hasSuffix("douyin.com") {
                let signed = candidate.contains("X-Bogus=")
                    ? candidate
                    : DouyinAPISupport.signDouyinURLWithXBogus(candidate)
                if isWatermarked {
                    watermarked = watermarked ?? (signed, headers)
                    continue
                }
                return (signed, headers)
            }
            if isWatermarked {
                watermarked = watermarked ?? (candidate, headers)
            } else {
                fallbackCDN = fallbackCDN ?? (candidate, headers)
            }
        }

        if let fallbackCDN { return fallbackCDN }

        if let uri = (playAddr["uri"] as? String)?.nilIfEmpty
            ?? (video["vid"] as? String)?.nilIfEmpty
        {
            let token = msToken ?? DouyinAPISupport.resolveMsToken(cookieMap: [:])
            let query = DouyinAPISupport.defaultWebQueryItems(
                msToken: token,
                extra: [
                    .init(name: "video_id", value: uri),
                    .init(name: "ratio", value: "1080p"),
                    .init(name: "line", value: "0"),
                    .init(name: "is_play_url", value: "1"),
                    .init(name: "watermark", value: "0"),
                    .init(name: "source", value: "PackSourceEnum_PUBLISH")
                ]
            )
            if let signed = DouyinAPISupport.signedURL(path: "/aweme/v1/play/", queryItems: query) {
                return (signed.absoluteString, downloadHeaders())
            }
        }

        return watermarked
    }

    private static func pickPreferredPlayAddr(from video: [String: Any]) -> [String: Any]? {
        if let fromBitrate = pickHighestBitratePlayAddr(from: video) {
            return fromBitrate
        }
        for key in ["play_addr_h264", "play_addr_265", "play_addr_256", "play_addr"] {
            if let addr = video[key] as? [String: Any] { return addr }
        }
        return nil
    }

    private static func pickHighestBitratePlayAddr(from video: [String: Any]) -> [String: Any]? {
        guard let bitRates = video["bit_rate"] as? [[String: Any]], !bitRates.isEmpty else { return nil }
        var best: (Int, [String: Any])?
        for entry in bitRates {
            guard let playAddr = entry["play_addr"] as? [String: Any] else { continue }
            let bitrate = entry["bit_rate"] as? Int ?? 0
            if best == nil || bitrate > best!.0 {
                best = (bitrate, playAddr)
            }
        }
        return best?.1
    }

    private static func downloadHeaders() -> [String: String] {
        [
            "User-Agent": DouyinAPISupport.apiUserAgent,
            "Referer": "\(DouyinAPISupport.origin)/",
            "Origin": DouyinAPISupport.origin
        ]
    }

    private static func extractThumbnail(from detail: [String: Any]) -> String? {
        guard let video = detail["video"] as? [String: Any],
              let cover = video["cover"] as? [String: Any],
              let urlList = cover["url_list"] as? [Any]
        else { return nil }
        for value in urlList {
            let url = String(describing: value).trimmingCharacters(in: .whitespacesAndNewlines)
            if url.lowercased().hasPrefix("http") { return url }
        }
        return nil
    }

    private static func extractDuration(from detail: [String: Any]) -> Int {
        guard let video = detail["video"] as? [String: Any] else { return 0 }
        let raw: Int = {
            if let value = video["duration"] as? Int { return value }
            if let value = video["duration"] as? Double { return Int(value) }
            return 0
        }()
        guard raw > 0 else { return 0 }
        return raw > 1000 ? raw / 1000 : raw
    }

    private static func extractAvailableHeights(from detail: [String: Any]) -> [Int] {
        guard let video = detail["video"] as? [String: Any] else { return [] }
        var heights = Set<Int>()
        if let bitRates = video["bit_rate"] as? [[String: Any]] {
            for entry in bitRates {
                if let height = entry["height"] as? Int, height > 0 {
                    heights.insert(height)
                }
                if let playAddr = entry["play_addr"] as? [String: Any],
                   let height = playAddr["height"] as? Int, height > 0
                {
                    heights.insert(height)
                }
            }
        }
        if let playAddr = video["play_addr"] as? [String: Any],
           let height = playAddr["height"] as? Int, height > 0
        {
            heights.insert(height)
        }
        return heights.sorted(by: >)
    }

    private static func isGallery(_ detail: [String: Any]) -> Bool {
        if detail["images"] != nil || detail["image_post_info"] != nil { return true }
        if let awemeType = detail["aweme_type"] as? Int, galleryAwemeTypes.contains(awemeType) {
            return true
        }
        return false
    }

    private static func hasVideoSource(_ detail: [String: Any]) -> Bool {
        guard let video = detail["video"] as? [String: Any] else { return false }
        if let urlList = video["play_addr"] as? [String: Any],
           let urls = urlList["url_list"] as? [Any], !urls.isEmpty
        {
            return true
        }
        if let bitRates = video["bit_rate"] as? [[String: Any]], !bitRates.isEmpty {
            return true
        }
        return false
    }

    private static func normalizedURL(_ raw: String) -> URL? {
        let withProto = raw.lowercased().hasPrefix("http") ? raw : "https://\(raw)"
        return URL(string: withProto)
    }
}

private final class RedirectBlocker: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    static let shared = RedirectBlocker()

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
