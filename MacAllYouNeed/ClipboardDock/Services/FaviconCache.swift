import AppKit
import Core
import Foundation

actor FaviconCache {
    private var memory: [String: NSImage] = [:]
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.urlCache = URLCache(memoryCapacity: 8 * 1024 * 1024, diskCapacity: 32 * 1024 * 1024)
        config.timeoutIntervalForRequest = 5
        session = URLSession(configuration: config)
    }

    func favicon(for url: URL) async -> NSImage? {
        guard AppGroupSettings.defaults.bool(forKey: "linkCard.fetchFavicons") else { return nil }
        guard let host = url.host else { return nil }
        if let cached = memory[host] { return cached }
        guard let iconURL = URL(string: "https://\(host)/favicon.ico") else { return nil }
        do {
            let (data, response) = try await session.data(from: iconURL)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  let image = NSImage(data: data) else {
                return nil
            }
            memory[host] = image
            return image
        } catch {
            return nil
        }
    }
}
