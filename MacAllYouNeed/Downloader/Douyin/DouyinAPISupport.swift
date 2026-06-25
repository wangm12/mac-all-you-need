import CryptoKit
import Foundation

/// Shared Douyin web API helpers (cookies, msToken, X-Bogus signing).
/// Ported from the in-app profile lister and reference douyin-downloader project.
enum DouyinAPISupport {
    static let apiUserAgent =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36"
    static let referer = "https://www.douyin.com/?recommend=1"
    static let origin = "https://www.douyin.com"

    static func cookieMap(from cookieFile: URL?) -> [String: String] {
        guard let cookieFile, let text = try? String(contentsOf: cookieFile, encoding: .utf8) else { return [:] }
        var out: [String: String] = [:]
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let raw = String(line)
            if raw.hasPrefix("#") { continue }
            let parts = raw.split(separator: "\t", omittingEmptySubsequences: false)
            guard parts.count >= 7 else { continue }
            let domain = String(parts[0]).lowercased()
            guard domain.contains("douyin")
                || domain.contains("iesdouyin")
                || domain.contains("bytedance")
                || domain.contains("toutiao")
                || domain.contains("snssdk")
                || domain.contains("amemv")
            else { continue }
            out[String(parts[5])] = String(parts[6])
        }
        return out
    }

    struct RequestContext: Sendable {
        let cookieMap: [String: String]
        let msToken: String
    }

    /// One resolved `msToken` per request — use for both query params and the Cookie header.
    static func requestContext(from cookieFile: URL?) -> RequestContext? {
        let map = cookieMap(from: cookieFile)
        guard !map.isEmpty else { return nil }
        return RequestContext(cookieMap: map, msToken: resolveMsToken(cookieMap: map))
    }

    /// Cookie header for Douyin API calls. Injects a synthetic `msToken` when the synced file lacks one.
    static func cookieHeader(from cookieFile: URL?) -> String? {
        guard let context = requestContext(from: cookieFile) else { return nil }
        return cookieHeader(cookieMap: context.cookieMap, msToken: context.msToken)
    }

    static func cookieHeader(cookieMap: [String: String], msToken: String) -> String? {
        guard !cookieMap.isEmpty else { return nil }
        var map = cookieMap
        map["msToken"] = msToken
        return map.map { "\($0.key)=\($0.value)" }.joined(separator: "; ")
    }

    static func resolveMsToken(cookieMap: [String: String]) -> String {
        if let token = cookieMap["msToken"]?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
            return token
        }
        let chars = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")
        let body = (0 ..< 182).map { _ in String(chars.randomElement() ?? "A") }.joined()
        return body + "=="
    }

    static func defaultWebQueryItems(msToken: String, extra: [URLQueryItem] = []) -> [URLQueryItem] {
        var query: [URLQueryItem] = [
            .init(name: "device_platform", value: "webapp"),
            .init(name: "aid", value: "6383"),
            .init(name: "channel", value: "channel_pc_web"),
            .init(name: "update_version_code", value: "170400"),
            .init(name: "pc_client_type", value: "1"),
            .init(name: "pc_libra_divert", value: "Windows"),
            .init(name: "version_code", value: "290100"),
            .init(name: "version_name", value: "29.1.0"),
            .init(name: "cookie_enabled", value: "true"),
            .init(name: "screen_width", value: "1536"),
            .init(name: "screen_height", value: "864"),
            .init(name: "browser_language", value: "zh-CN"),
            .init(name: "browser_platform", value: "Win32"),
            .init(name: "browser_name", value: "Chrome"),
            .init(name: "browser_version", value: "139.0.0.0"),
            .init(name: "browser_online", value: "true"),
            .init(name: "engine_name", value: "Blink"),
            .init(name: "engine_version", value: "139.0.0.0"),
            .init(name: "os_name", value: "Windows"),
            .init(name: "os_version", value: "10"),
            .init(name: "cpu_core_num", value: "16"),
            .init(name: "device_memory", value: "8"),
            .init(name: "platform", value: "PC"),
            .init(name: "downlink", value: "10"),
            .init(name: "effective_type", value: "4g"),
            .init(name: "round_trip_time", value: "200"),
            .init(name: "support_h265", value: "1"),
            .init(name: "support_dash", value: "1"),
            .init(name: "uifid", value: ""),
            .init(name: "msToken", value: msToken)
        ]
        let overrides = Dictionary(uniqueKeysWithValues: extra.map { ($0.name, $0.value ?? "") })
        query = query.map { item in
            guard let override = overrides[item.name] else { return item }
            return URLQueryItem(name: item.name, value: override)
        }
        let baseNames = Set(query.map(\.name))
        for item in extra where !baseNames.contains(item.name) {
            query.append(item)
        }
        return query
    }

    static func signedURL(path: String, queryItems: [URLQueryItem]) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.douyin.com"
        components.path = path
        components.queryItems = queryItems
        guard let base = components.url?.absoluteString else { return nil }
        return URL(string: signDouyinURLWithXBogus(base))
    }

    /// Percent-encodes a query value to match Python's `urllib.parse.quote_plus`
    /// (only `A-Za-z0-9` and `_.-~` are left unescaped). Required so the signed
    /// query string is byte-identical to what we transmit.
    private static let queryAllowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "_.-~")
        return set
    }()

    private static func encodedQueryString(_ items: [URLQueryItem]) -> String {
        items.map { item in
            let name = item.name.addingPercentEncoding(withAllowedCharacters: queryAllowed) ?? item.name
            let rawValue = item.value ?? ""
            let value = rawValue.addingPercentEncoding(withAllowedCharacters: queryAllowed) ?? rawValue
            return "\(name)=\(value)"
        }
        .joined(separator: "&")
    }

    /// Signs a Douyin web API request with `a_bogus` (required for the
    /// `/aweme/v1/web/aweme/detail/` endpoint — `X-Bogus` returns empty 200s there).
    static func signedURLWithABogus(path: String, queryItems: [URLQueryItem]) -> URL? {
        let query = encodedQueryString(queryItems)
        let fingerprint = DouyinABogus.chromeFingerprint()
        let signature = DouyinABogus.generate(
            params: query,
            body: "",
            userAgent: apiUserAgent,
            fingerprint: fingerprint
        )
        let full = "https://www.douyin.com\(path)?\(query)&a_bogus=\(signature.aBogus)"
        return URL(string: full)
    }

    static func signDouyinURLWithXBogus(_ fullURLWithQuery: String) -> String {
        let ua = apiUserAgent
        let uaKey: [UInt8] = [0, 1, 12]
        let character = Array("Dkdpgh4ZKsQB80/Mfvw36XI1R25-WUAlEi7NLboqYTOPuzmFjJnryx9HVGcaStCe=")

        func md5Hex(_ bytes: [UInt8]) -> String {
            Insecure.MD5.hash(data: Data(bytes)).map { String(format: "%02x", $0) }.joined()
        }
        func md5Hex(_ string: String) -> String {
            md5Hex(Array(string.utf8))
        }
        func hexToBytes(_ hex: String) -> [UInt8] {
            stride(from: 0, to: hex.count, by: 2).compactMap { idx in
                let start = hex.index(hex.startIndex, offsetBy: idx)
                let end = hex.index(start, offsetBy: 2, limitedBy: hex.endIndex) ?? hex.endIndex
                return UInt8(hex[start ..< end], radix: 16)
            }
        }
        func rc4(key: [UInt8], data: [UInt8]) -> [UInt8] {
            var s = Array(0 ... 255)
            var j = 0
            for i in 0 ..< 256 {
                j = (j + s[i] + Int(key[i % key.count])) % 256
                s.swapAt(i, j)
            }
            var i = 0
            j = 0
            var out: [UInt8] = []
            out.reserveCapacity(data.count)
            for byte in data {
                i = (i + 1) % 256
                j = (j + s[i]) % 256
                s.swapAt(i, j)
                out.append(byte ^ UInt8(s[(s[i] + s[j]) % 256]))
            }
            return out
        }

        let uaRC4 = rc4(key: uaKey, data: Array(ua.utf8))
        let uaBase64 = Data(uaRC4).base64EncodedString()
        let uaMd5Array = hexToBytes(md5Hex(uaBase64))

        let emptyMd5 = md5Hex(hexToBytes(md5Hex("d41d8cd98f00b204e9800998ecf8427e")))
        let emptyMd5Array = hexToBytes(emptyMd5)

        let urlMd5 = md5Hex(hexToBytes(md5Hex(fullURLWithQuery)))
        let urlMd5Array = hexToBytes(urlMd5)

        let timer = Int(Date().timeIntervalSince1970)
        let ct = 536_919_696
        var newArray: [UInt8] = [
            64, 0, 1, 12,
            urlMd5Array[14], urlMd5Array[15],
            emptyMd5Array[14], emptyMd5Array[15],
            uaMd5Array[14], uaMd5Array[15],
            UInt8((timer >> 24) & 255), UInt8((timer >> 16) & 255), UInt8((timer >> 8) & 255), UInt8(timer & 255),
            UInt8((ct >> 24) & 255), UInt8((ct >> 16) & 255), UInt8((ct >> 8) & 255), UInt8(ct & 255)
        ]
        var xor = newArray[0]
        for v in newArray.dropFirst() { xor ^= v }
        newArray.append(xor)

        var merged: [UInt8] = []
        merged.reserveCapacity(newArray.count)
        for i in stride(from: 0, to: newArray.count, by: 2) { merged.append(newArray[i]) }
        for i in stride(from: 1, to: newArray.count, by: 2) { merged.append(newArray[i]) }

        let rc4Data = rc4(key: [255], data: merged)
        let garbled = [2, 255] + rc4Data
        var xbogus = ""
        for i in stride(from: 0, to: garbled.count, by: 3) {
            let a = Int(garbled[i])
            let b = Int(i + 1 < garbled.count ? garbled[i + 1] : 0)
            let c = Int(i + 2 < garbled.count ? garbled[i + 2] : 0)
            let x = ((a & 255) << 16) | ((b & 255) << 8) | (c & 255)
            xbogus.append(character[(x & 0xFC0000) >> 18])
            xbogus.append(character[(x & 0x03F000) >> 12])
            xbogus.append(character[(x & 0x000FC0) >> 6])
            xbogus.append(character[x & 0x00003F])
        }
        return fullURLWithQuery + "&X-Bogus=" + xbogus
    }
}
