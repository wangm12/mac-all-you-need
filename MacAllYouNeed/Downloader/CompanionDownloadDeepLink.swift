import Foundation

/// Parses `mayn://companion/...` URLs opened by the Chrome extension.
enum CompanionDownloadDeepLink {
    enum Action: Equatable, Sendable {
        case wake
        case download(Payload)
    }

    struct Payload: Equatable, Sendable {
        let url: String
        let title: String?
        let mediaType: String?
        let referer: String?
        let awemeID: String?
        let pageURL: String?
    }

    static func parse(_ rawURL: URL) -> Action? {
        guard rawURL.scheme?.lowercased() == "mayn" else { return nil }
        guard rawURL.host?.lowercased() == "companion" else { return nil }

        let path = rawURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if path == "wake" {
            return .wake
        }
        guard path == "download" else { return nil }

        guard let components = URLComponents(url: rawURL, resolvingAgainstBaseURL: false) else { return nil }
        var query: [String: String] = [:]
        for item in components.queryItems ?? [] {
            guard let value = item.value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
                continue
            }
            query[item.name] = value
        }

        guard let url = query["url"], !url.isEmpty else { return nil }

        return .download(
            Payload(
                url: url,
                title: query["title"],
                mediaType: query["type"],
                referer: query["referer"],
                awemeID: query["awemeId"],
                pageURL: query["pageURL"]
            )
        )
    }
}
