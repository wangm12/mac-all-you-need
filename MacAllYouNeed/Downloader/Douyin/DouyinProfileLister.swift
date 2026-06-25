import Core
import Foundation
import os

struct DouyinProfilePostRow: Sendable, Equatable, Identifiable {
    var id: String { awemeId }
    let awemeId: String
    let title: String
    let author: String
    let thumbnail: String
    let pageURL: String
}

struct DouyinProfileListResult: Sendable, Equatable {
    var items: [DouyinProfilePostRow]
    var cursor: String?
    var hasMore: Bool
    var warnings: [String]

    static let maxLoadAllItems = 2000
    static let maxLoadAllPages = 50
}

enum DouyinProfileLister {
    private static let log = Logger(subsystem: "com.macallyouneed.app", category: "douyin-profile")
    private struct ItemListBlob {
        let items: [[String: Any]]
    }

    private struct SignedPage {
        let rows: [DouyinProfilePostRow]
        let nextCursor: String?
        let hasMore: Bool
        let paginationRestricted: Bool
    }

    static func extractSecUid(from url: String) -> String? {
        guard let parsed = normalizedURL(url) else { return nil }
        let host = parsed.host?.lowercased() ?? ""
        guard host == "douyin.com" || host.hasSuffix(".douyin.com") else { return nil }
        guard let range = parsed.path.range(of: "/user/") else { return nil }
        let remainder = parsed.path[range.upperBound...]
        let secUid = remainder.split(separator: "/").first.map(String.init) ?? ""
        return secUid.isEmpty ? nil : secUid
    }

    static func listFirstPage(
        profileURL: String,
        ytdlp: URL,
        cookieFile: URL?
    ) async throws -> DouyinProfileListResult {
        let targetURL = canonicalProfileURL(from: profileURL) ?? profileURL
        log.info("listFirstPage start targetURL=\(targetURL, privacy: .public) cookieFile=\(cookieFile?.path ?? "nil", privacy: .public)")

        if let playlist = try? await PlaylistEntryLister.list(url: targetURL, ytdlp: ytdlp, cookieFile: cookieFile),
           !playlist.items.isEmpty
        {
            log.info("listFirstPage success via yt-dlp rows=\(playlist.items.count)")
            let rows = playlist.items.map { item in
                DouyinProfilePostRow(
                    awemeId: item.id,
                    title: item.title,
                    author: item.channel.isEmpty ? playlist.channel : item.channel,
                    thumbnail: item.thumbnail,
                    pageURL: item.pageURL.isEmpty ? targetURL : item.pageURL
                )
            }
            return DouyinProfileListResult(items: rows, cursor: nil, hasMore: false, warnings: [])
        }
        log.info("listFirstPage yt-dlp path produced no rows")

        var mergedRows: [DouyinProfilePostRow] = []
        var seen = Set<String>()
        var warnings: [String] = []
        var cursor: String?
        var hasMore = false

        if let secUid = extractSecUid(from: targetURL),
           let apiPage = try? await fetchSignedPage(secUid: secUid, maxCursor: nil, cookieFile: cookieFile)
        {
            for row in apiPage.rows where seen.insert(row.awemeId).inserted {
                mergedRows.append(row)
            }
            cursor = apiPage.nextCursor
            hasMore = apiPage.hasMore
            if apiPage.paginationRestricted {
                warnings.append("Douyin limited API pagination. Try Load in browser for missing posts.")
            }
        }

        if let htmlRows = try? await listFromHTML(profileURL: targetURL, cookieFile: cookieFile), !htmlRows.isEmpty {
            for row in htmlRows where seen.insert(row.awemeId).inserted {
                mergedRows.append(row)
            }
        }
        if !mergedRows.isEmpty {
            log.info("listFirstPage success merged rows=\(mergedRows.count) hasMore=\(hasMore)")
            return DouyinProfileListResult(items: mergedRows, cursor: cursor, hasMore: hasMore, warnings: warnings)
        }
        log.error("listFirstPage failed: no entries from yt-dlp and HTML")

        throw PlaylistListError.noEntries
    }

    static func listNextPage(
        profileURL: String,
        cursor: String,
        cookieFile: URL?
    ) async throws -> DouyinProfileListResult {
        guard let secUid = extractSecUid(from: profileURL),
              let maxCursor = decodeCursor(cursor)
        else { throw PlaylistListError.noEntries }

        try await Task.sleep(nanoseconds: 300_000_000)
        let page = try await fetchSignedPage(secUid: secUid, maxCursor: maxCursor, cookieFile: cookieFile)
        return DouyinProfileListResult(
            items: page.rows,
            cursor: page.nextCursor,
            hasMore: page.hasMore,
            warnings: page.paginationRestricted ? ["Douyin limited API pagination. Try Load in browser."] : []
        )
    }

    static func listFromHTML(profileURL: String, cookieFile: URL? = nil) async throws -> [DouyinProfilePostRow] {
        guard let url = normalizedURL(profileURL) else { throw PlaylistListError.noEntries }
        var request = URLRequest(url: url)
        request.setValue("https://www.douyin.com/", forHTTPHeaderField: "Referer")
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        if let cookieHeader = DouyinAPISupport.cookieHeader(from: cookieFile), !cookieHeader.isEmpty {
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
            log.info("listFromHTML sending cookies count=\(cookieHeader.split(separator: ";").count)")
        } else {
            log.info("listFromHTML no cookie header available")
        }
        let (data, _) = try await URLSession.shared.data(for: request)
        let html = String(data: data, encoding: .utf8) ?? ""
        let rows = parsePosts(from: html, profileURL: profileURL)
        log.info("listFromHTML htmlBytes=\(html.utf8.count) parsedRows=\(rows.count)")
        return rows
    }

    static func listFromSignedAPI(profileURL: String, cookieFile: URL?) async throws -> [DouyinProfilePostRow] {
        guard let secUid = extractSecUid(from: profileURL) else { throw PlaylistListError.noEntries }
        return try await fetchSignedPage(secUid: secUid, maxCursor: nil, cookieFile: cookieFile).rows
    }

    static func parsePosts(from html: String, profileURL: String) -> [DouyinProfilePostRow] {
        let fromEmbedded = parseEmbeddedItemLists(from: html, profileURL: profileURL)
        if !fromEmbedded.isEmpty {
            return fromEmbedded
        }

        let awemePatterns = [
            #""aweme_id"\s*:\s*"(\d+)""#,
            #""aweme_id"\s*:\s*(\d+)"#,
            #""awemeId"\s*:\s*"(\d+)""#,
            #""awemeId"\s*:\s*(\d+)"#
        ]
        let urlPatterns = [
            #"/video/(\d{10,})"#,
            #"https?://www\.douyin\.com/video/(\d{10,})"#
        ]
        var seen = Set<String>()
        var rows: [DouyinProfilePostRow] = []

        for pattern in awemePatterns + urlPatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(html.startIndex ..< html.endIndex, in: html)
            for match in regex.matches(in: html, range: range) {
                guard match.numberOfRanges > 1,
                      let idRange = Range(match.range(at: 1), in: html) else { continue }
                let awemeId = String(html[idRange])
                guard seen.insert(awemeId).inserted else { continue }
                let pageURL = "https://www.douyin.com/video/\(awemeId)"
                rows.append(DouyinProfilePostRow(
                    awemeId: awemeId,
                    title: "Douyin post \(awemeId)",
                    author: "",
                    thumbnail: "",
                    pageURL: pageURL
                ))
                if rows.count >= DouyinProfileListResult.maxLoadAllItems { return rows }
            }
        }
        return rows
    }

    private static func parseEmbeddedItemLists(from html: String, profileURL: String) -> [DouyinProfilePostRow] {
        var roots: [[String: Any]] = []
        for marker in ["_ROUTER_DATA", "__MODERN_ROUTER_DATA__", "SIGI_STATE", "SUPER_DATA"] {
            if let root = parseJSONRoot(afterMarker: marker, in: html) {
                roots.append(root)
            }
        }
        if let renderData = parseRenderData(in: html) {
            roots.append(renderData)
        }
        if let nextData = parseNextData(in: html) {
            roots.append(nextData)
        }

        var blobs: [ItemListBlob] = []
        for root in roots {
            collectItemListBlobs(from: root, into: &blobs)
        }

        var seen = Set<String>()
        var rows: [DouyinProfilePostRow] = []
        for blob in blobs {
            for item in blob.items {
                guard let row = rowFromAwemeItem(item, profileURL: profileURL) else { continue }
                guard seen.insert(row.awemeId).inserted else { continue }
                rows.append(row)
                if rows.count >= DouyinProfileListResult.maxLoadAllItems {
                    return rows
                }
            }
        }
        return rows
    }

    static func rowFromAwemeItem(_ item: [String: Any], profileURL: String) -> DouyinProfilePostRow? {
        let idRaw = item["aweme_id"] ?? item["awemeId"]
        let awemeId = String(describing: idRaw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard awemeId.range(of: #"^\d{10,}$"#, options: .regularExpression) != nil else { return nil }

        let title = (item["desc"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let author = ((item["author"] as? [String: Any])?["nickname"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let thumbnail: String = {
            if let video = item["video"] as? [String: Any],
               let cover = video["cover"] as? [String: Any],
               let urlList = cover["url_list"] as? [Any]
            {
                for value in urlList {
                    let url = String(describing: value).trimmingCharacters(in: .whitespacesAndNewlines)
                    if url.lowercased().hasPrefix("http") { return url }
                }
            }
            if let images = item["images"] as? [[String: Any]], let first = images.first,
               let urlList = first["url_list"] as? [Any]
            {
                for value in urlList.reversed() {
                    let url = String(describing: value).trimmingCharacters(in: .whitespacesAndNewlines)
                    if url.lowercased().hasPrefix("http") { return url }
                }
            }
            return ""
        }()

        let pageURL = "https://www.douyin.com/video/\(awemeId)"
        return DouyinProfilePostRow(
            awemeId: awemeId,
            title: (title?.isEmpty == false ? String(title!.prefix(200)) : "Douyin post \(awemeId)"),
            author: author,
            thumbnail: thumbnail,
            pageURL: pageURL
        )
    }

    private static func collectItemListBlobs(from value: Any, into blobs: inout [ItemListBlob]) {
        if let dict = value as? [String: Any] {
            if let itemList = dict["item_list"] as? [Any], let first = itemList.first as? [String: Any] {
                if first["aweme_id"] != nil || first["awemeId"] != nil {
                    let mapped = itemList.compactMap { $0 as? [String: Any] }
                    if !mapped.isEmpty {
                        blobs.append(ItemListBlob(items: mapped))
                    }
                }
            }
            for nested in dict.values {
                collectItemListBlobs(from: nested, into: &blobs)
            }
            return
        }
        if let array = value as? [Any] {
            for nested in array {
                collectItemListBlobs(from: nested, into: &blobs)
            }
        }
    }

    private static func parseJSONRoot(afterMarker marker: String, in html: String) -> [String: Any]? {
        guard let markerRange = html.range(of: marker) else { return nil }
        guard let json = extractBalancedJSONObject(in: html, from: markerRange.upperBound),
              let data = json.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return parsed
    }

    private static func parseRenderData(in html: String) -> [String: Any]? {
        let pattern = #"<script[^>]*\bid=["']RENDER_DATA["'][^>]*>([\s\S]*?)</script>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex ..< html.endIndex, in: html)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: html)
        else { return nil }
        let raw = String(html[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let decoded = raw.removingPercentEncoding,
              let data = decoded.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return parsed
    }

    private static func parseNextData(in html: String) -> [String: Any]? {
        let pattern = #"<script[^>]*\bid=["']__NEXT_DATA__["'][^>]*>([\s\S]*?)</script>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex ..< html.endIndex, in: html)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: html),
              let data = String(html[range]).trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return parsed
    }

    private static func extractBalancedJSONObject(in text: String, from start: String.Index) -> String? {
        guard let firstBrace = text[start...].firstIndex(of: "{") else { return nil }

        var idx = firstBrace
        var depth = 0
        var inString = false
        var escaped = false
        var endIndex: String.Index?

        while idx < text.endIndex {
            let ch = text[idx]
            if inString {
                if escaped {
                    escaped = false
                } else if ch == "\\" {
                    escaped = true
                } else if ch == "\"" {
                    inString = false
                }
            } else {
                if ch == "\"" {
                    inString = true
                } else if ch == "{" {
                    depth += 1
                } else if ch == "}" {
                    depth -= 1
                    if depth == 0 {
                        endIndex = text.index(after: idx)
                        break
                    }
                }
            }
            idx = text.index(after: idx)
        }

        guard let endIndex else { return nil }
        return String(text[firstBrace ..< endIndex])
    }

    private static func canonicalProfileURL(from raw: String) -> String? {
        guard let secUid = extractSecUid(from: raw) else { return nil }
        return "https://www.douyin.com/user/\(secUid)"
    }

    private static func normalizedURL(_ raw: String) -> URL? {
        let withProto = raw.lowercased().hasPrefix("http") ? raw : "https://\(raw)"
        return URL(string: withProto)
    }

    private static func signedAwemePostURL(secUid: String, cookieFile: URL?) -> URL? {
        let msToken = DouyinAPISupport.resolveMsToken(cookieMap: DouyinAPISupport.cookieMap(from: cookieFile))
        return signedAwemePostURL(secUid: secUid, maxCursor: nil, cookieFile: cookieFile, msToken: msToken)
    }

    private static func signedAwemePostURL(
        secUid: String,
        maxCursor: String?,
        cookieFile: URL?,
        msToken: String
    ) -> URL? {
        let requestedCursor = (maxCursor ?? "0").trimmingCharacters(in: .whitespacesAndNewlines)
        let query = DouyinAPISupport.defaultWebQueryItems(
            msToken: msToken,
            extra: [
                .init(name: "sec_user_id", value: secUid),
                .init(name: "max_cursor", value: requestedCursor.isEmpty ? "0" : requestedCursor),
                .init(name: "count", value: "35"),
                .init(name: "locate_query", value: "false"),
                .init(name: "show_live_replay_strategy", value: "1"),
                .init(name: "need_time_list", value: "1"),
                .init(name: "time_list_query", value: "0"),
                .init(name: "whale_cut_token", value: ""),
                .init(name: "cut_version", value: "1"),
                .init(name: "publish_video_strategy_type", value: "2")
            ]
        )
        return DouyinAPISupport.signedURLWithABogus(path: "/aweme/v1/web/aweme/post/", queryItems: query)
    }

    private static func fetchSignedPage(secUid: String, maxCursor: String?, cookieFile: URL?) async throws -> SignedPage {
        let cookieMap = DouyinAPISupport.cookieMap(from: cookieFile)
        let msToken = DouyinAPISupport.resolveMsToken(cookieMap: cookieMap)
        let retryDelays: [TimeInterval] = [1, 2, 5]
        var lastData = Data()
        var lastRoot: [String: Any] = [:]
        var awemeList: [[String: Any]] = []

        for attempt in 0 ..< 3 {
            guard let requestURL = signedAwemePostURL(
                secUid: secUid,
                maxCursor: maxCursor,
                cookieFile: cookieFile,
                msToken: msToken
            )
            else { throw PlaylistListError.noEntries }

            var request = URLRequest(url: requestURL)
            request.setValue(
                "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36",
                forHTTPHeaderField: "User-Agent"
            )
            request.setValue("https://www.douyin.com/?recommend=1", forHTTPHeaderField: "Referer")
            request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
            request.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
            if let cookieHeader = DouyinAPISupport.cookieHeader(cookieMap: cookieMap, msToken: msToken),
               !cookieHeader.isEmpty
            {
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
                throw PlaylistListError.noEntries
            }

            guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                if attempt < 2 {
                    try await Task.sleep(nanoseconds: UInt64(retryDelays[attempt] * 1_000_000_000))
                    continue
                }
                throw PlaylistListError.noEntries
            }
            let payload = (root["data"] as? [String: Any]) ?? root
            let list = payload["aweme_list"] as? [[String: Any]] ?? root["aweme_list"] as? [[String: Any]] ?? []
            let statusCode = (payload["status_code"] as? Int) ?? (root["status_code"] as? Int) ?? 0
            let isAntiBotSignal = list.isEmpty && statusCode == 0 && !data.isEmpty

            lastData = data
            lastRoot = root
            awemeList = list

            if !isAntiBotSignal { break }
            log.info("fetchSignedPage anti-bot signal attempt=\(attempt) secUid=\(secUid, privacy: .public)")
            if attempt < 2 {
                try await Task.sleep(nanoseconds: UInt64(retryDelays[attempt] * 1_000_000_000))
            }
        }

        let root = lastRoot
        let payload = (root["data"] as? [String: Any]) ?? root

        var seen = Set<String>()
        var rows: [DouyinProfilePostRow] = []
        for item in awemeList {
            guard let row = rowFromAwemeItem(item, profileURL: "https://www.douyin.com/user/\(secUid)") else { continue }
            guard seen.insert(row.awemeId).inserted else { continue }
            rows.append(row)
            if rows.count >= DouyinProfileListResult.maxLoadAllItems { break }
        }

        let requested = (maxCursor ?? "0").trimmingCharacters(in: .whitespacesAndNewlines)
        let maxRaw = payload["max_cursor"] ?? root["max_cursor"]
        let responseCursor = String(describing: maxRaw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let hasMoreRaw = payload["has_more"] ?? root["has_more"]
        let hasMoreApi = (hasMoreRaw as? Bool) == true
            || String(describing: hasMoreRaw ?? "").lowercased() == "true"
            || String(describing: hasMoreRaw ?? "") == "1"
        let cursorAdvanced = !requested.isEmpty && !responseCursor.isEmpty && requested != responseCursor
        let firstPageMaybeMore = (requested == "0" || requested.isEmpty)
            && !hasMoreApi
            && awemeList.count >= 5
            && !responseCursor.isEmpty
            && responseCursor != "0"
        let heuristicMore = !hasMoreApi && cursorAdvanced && responseCursor != "0"
        let finalStatusCode = (payload["status_code"] as? Int) ?? (root["status_code"] as? Int) ?? 0
        let paginationRestricted = rows.isEmpty && finalStatusCode == 0
        let hasMore = !paginationRestricted && (hasMoreApi || heuristicMore || firstPageMaybeMore)
        let nextCursor = hasMore && !responseCursor.isEmpty ? encodeCursor(responseCursor) : nil

        return SignedPage(rows: rows, nextCursor: nextCursor, hasMore: hasMore, paginationRestricted: paginationRestricted)
    }

    private static func encodeCursor(_ maxCursor: String) -> String {
        let payload = #"{"v":1,"mc":"\#(maxCursor)"}"#
        return Data(payload.utf8).base64EncodedString()
    }

    private static func decodeCursor(_ cursor: String?) -> String? {
        guard let cursor, !cursor.isEmpty,
              let data = Data(base64Encoded: cursor),
              let raw = String(data: data, encoding: .utf8),
              let parsedData = raw.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: parsedData) as? [String: Any],
              let mc = parsed["mc"] as? String,
              !mc.isEmpty
        else { return nil }
        return mc
    }

}
